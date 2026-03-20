#!/bin/bash
# MagnusBilling 7 Installation Script for Ubuntu 24.04
# Adapted from original install.sh by MagnusSolution

echo "=================== MagnusBilling 7 - Ubuntu 24.04 =========================";
echo "_      _                               ______ _ _ _ _                ";
echo "|\    /|                               | ___ (_) | (_)               ";
echo "| \  / | ___  ____  _ __  _   _  _____ | |_/ /_| | |_ _ __   ____    ";
echo "|  \/  |/   \/  _ \| '_ \| | | \| ___| | ___ \ | | | | '_ \ /  _ \   ";
echo "| |\/| |  | |  (_| | | | | |_| ||____  | |_/ / | | | | | | |  (_| |  ";
echo "|_|  |_|\___|\___  |_| | |_____|_____|  \___/|_|_|_|_|_| |_|\___  |  ";
echo "                _/ |                                           _/ |  ";
echo "               |__/                                           |__/   ";
echo "                                                                     ";
echo "======================= VOIP SYSTEM FOR LINUX =======================";

if [[ -f /var/www/html/mbilling/index.php ]]; then
  echo "This server already has MagnusBilling installed";
  exit;
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ $ID == "ubuntu" && $VERSION_ID == "24.04" ]]; then
        DIST="UBUNTU24"
        HTTP_DIR="/etc/apache2/"
        HTTP_CONFIG=${HTTP_DIR}"apache2.conf"
        MYSQL_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"
        APACHE_USER="www-data"
    else
        echo "This script is optimized for Ubuntu 24.04. Detected: $ID $VERSION_ID"
        exit 1
    fi
else
    echo "Linux distribution not supported."
    exit 1
fi

genpasswd() {
    tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16 | xargs
}
password=$(genpasswd)
echo "$password" > /root/passwordMysql.log

# Update and install basic tools
apt-get update
apt-get install -y software-properties-common curl wget git unzip sudo locales firewalld fail2ban ntpsec htop sngrep whiptail rsyslog cron

# Set Locales
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# PHP 7.4 via PPA (Ubuntu 24 defaults to 8.3)
add-apt-repository -y ppa:ondrej/php
apt-get update
apt-get install -y php7.4 php7.4-fpm php7.4-cli php7.4-common php7.4-mysql php7.4-gd php7.4-curl php7.4-mbstring php7.4-xml php7.4-zip php7.4-dev php7.4-sqlite3 php7.4-pear libapache2-mod-php7.4

# Web Server and Database dependencies
apt-get install -y apache2 mariadb-server
apt-get install -y autoconf automake devscripts gawk g++ git-core xmlstarlet libjansson-dev odbcinst1debian2 libodbc1 odbcinst unixodbc unixodbc-dev
apt-get install -y uuid-dev libxml2 libxml2-dev openssl libcurl4-openssl-dev gettext gcc sqlite3 libsqlite3-dev subversion mpg123
apt-get install -y libncurses-dev 

# Configure PHP 7.4-FPM for Apache
a2enmod proxy_fcgi setenvif
a2enconf php7.4-fpm
systemctl restart apache2

# Download and Extract MagnusBilling
mkdir -p /var/www/html/mbilling
cd /var/www/html/mbilling
wget --no-check-certificate https://magnusbilling.org/download/MagnusBilling-current.tar.gz
tar xzf MagnusBilling-current.tar.gz

# Asterisk 13 Installation
echo '----------- Installing Asterisk 13 ----------'
cd /usr/src
rm -rf asterisk*
if [ -f "/var/www/html/mbilling/script/asterisk-13.35.0.tar.gz" ]; then
    cp /var/www/html/mbilling/script/asterisk-13.35.0.tar.gz .
else
    wget http://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-13.35.0.tar.gz
fi
tar xzvf asterisk-13.35.0.tar.gz
cd asterisk-13.35.0
useradd -c 'Asterisk PBX' -d /var/lib/asterisk asterisk -s /sbin/nologin
echo 'asterisk' > /etc/cron.deny
mkdir -p /var/run/asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk
contrib/scripts/install_prereq install
./configure
make menuselect.makeopts
menuselect/menuselect --enable res_config_mysql menuselect.makeopts
menuselect/menuselect --enable format_mp3 menuselect.makeopts
menuselect/menuselect --enable codec_opus menuselect.makeopts
contrib/scripts/get_mp3_source.sh
make -j$(nproc)
make install
make samples
make config
ldconfig

# Apache Security & Configuration
echo '
<IfModule mime_module>
AddType application/octet-stream .csv
</IfModule>

<Directory "/var/www/html">
    AllowOverride All
    DirectoryIndex index.htm index.html index.php index.php3 default.html index.cgi
</Directory>

<Directory "/var/www/html/mbilling/protected">
    deny from all
</Directory>

<Directory "/var/www/html/mbilling/yii">
    deny from all
</Directory>

<Directory "/var/www/html/mbilling/doc">
    deny from all
</Directory>

<Directory "/var/www/html/mbilling/resources/*log">
    deny from all
</Directory>

<Files "*.sql">
  deny from all
</Files>

<Files "*.log">
  deny from all
</Files>
' >> ${HTTP_CONFIG}

# PHP.ini Optimizations
PHP_INI="/etc/php/7.4/fpm/php.ini"
if [ -f "$PHP_INI" ]; then
    cp "$PHP_INI" "${PHP_INI}_old"
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 3M /" ${PHP_INI}
    sed -i "s/post_max_size = 8M/post_max_size = 20M/" ${PHP_INI}
    sed -i "s/max_execution_time = 30/max_execution_time = 90/" ${PHP_INI}
    sed -i "s/max_input_time = 60/max_input_time = 120/" ${PHP_INI}
    sed -i "s/memory_limit = 128M/memory_limit = 512M /" ${PHP_INI}
    systemctl restart php7.4-fpm
fi

# MariaDB Setup
systemctl enable --now mariadb
mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${password}');FLUSH PRIVILEGES;"

echo "
[mysqld]
user    = mysql
pid-file  = /var/run/mysqld/mysqld.pid
socket    = /var/run/mysqld/mysqld.sock
port    = 3306
max_connections = 500
key_buffer_size   = 64M
max_allowed_packet  = 64M
thread_stack    = 1M
thread_cache_size       = 8
query_cache_limit = 8M
query_cache_size        = 64M
secure_file_priv = /var/lib/mysql-files
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
tmp_table_size=128MB
open_files_limit=500000
" > ${MYSQL_CONFIG}
mkdir -p /var/lib/mysql-files
chown root:root /var/lib/mysql-files
chmod 755 /var/lib/mysql-files
systemctl restart mariadb

# MBilling Database Initialization
MBillingMysqlPass=$(genpasswd)
mysql -uroot -p${password} -e "CREATE DATABASE IF NOT EXISTS mbilling; CREATE USER 'mbillingUser'@'localhost' IDENTIFIED BY '${MBillingMysqlPass}'; GRANT ALL PRIVILEGES ON mbilling.* TO 'mbillingUser'@'localhost' WITH GRANT OPTION; GRANT FILE ON *.* TO 'mbillingUser'@'localhost'; FLUSH PRIVILEGES;"
mysql mbilling -uroot -p${password} < /var/www/html/mbilling/script/database.sql

# Asterisk Configuration Files
echo "[general]
dbhost = 127.0.0.1
dbname = mbilling
dbuser = mbillingUser
dbpass = $MBillingMysqlPass
" > /etc/asterisk/res_config_mysql.conf

cat > /etc/asterisk/manager.conf <<EOF
[general]
enabled = yes
port = 5038
bindaddr = 0.0.0.0
displayconnects = no

[magnus]
secret = magnussolution
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.0
read = system,call,log,verbose,agent,user,config,dtmf,reporting,cdr,dialplan
write = system,call,agent,user,config,command,reporting,originate
EOF

cat > /etc/asterisk/extensions_magnus.conf <<'EOF'
[billing]
exten => _[*0-9].,1,AGI("/var/www/html/mbilling/resources/asterisk/mbilling.php")
  same => n,Hangup()
exten => _+X.,1,Goto(billing,${EXTEN:1},1)
exten => h,1,hangup()
exten => *111,1,VoiceMailMain(${CHANNEL(peername)}@billing)
  same => n,Hangup()

[trunk_answer_handler]
exten => s,1,Set(MASTER_CHANNEL(TRUNKANSWERTIME)=${EPOCH})
  same => n,Return()
EOF

echo "#include extensions_magnus.conf" >> /etc/asterisk/extensions.conf
touch /etc/asterisk/extensions_magnus_did.conf
echo '#include extensions_magnus_did.conf' >> /etc/asterisk/extensions.conf

# Cron Jobs (using php7.4 explicitly)
CRONPATH='/var/spool/cron/crontabs/root'
echo "
8 8 * * * php7.4 /var/www/html/mbilling/cron.php servicescheck
* * * * * php7.4 /var/www/html/mbilling/cron.php callchart
1 * * * * php7.4 /var/www/html/mbilling/cron.php NotifyClient
1 22 * * * php7.4 /var/www/html/mbilling/cron.php DidCheck
1 23 * * * php7.4 /var/www/html/mbilling/cron.php PlanCheck
0 2 * * * php7.4 /var/www/html/mbilling/cron.php Backup
*/2 * * * * php7.4 /var/www/html/mbilling/cron.php SummaryTablesCdr
* * * * * php7.4 /var/www/html/mbilling/cron.php statussystem
*/5 * * * * php7.4 /var/www/html/mbilling/cron.php alarm
" > $CRONPATH
chmod 600 $CRONPATH

# Fail2Ban & Firewall
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=5060/udp
firewall-cmd --permanent --add-port=10000-20000/udp
firewall-cmd --reload

# Final Permissions
chown -R www-data:www-data /var/www/html/mbilling
chmod -R 755 /var/www/html/mbilling
chown -R asterisk:asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /etc/asterisk
chmod +x /var/www/html/mbilling/resources/asterisk/mbilling.php

echo "<?php header('Location: ./mbilling'); ?>" > /var/www/html/index.php

# Start Services
systemctl restart apache2 mariadb php7.4-fpm asterisk

whiptail --title "Installation Complete" --msgbox "MagnusBilling 7 has been installed successfully.\n\nAccess: http://your-ip/\nDefault Login: root / magnus\n\nMySQL Root Pass: $password\nMagnus DB Pass: $MBillingMysqlPass" 15 60
