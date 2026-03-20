<?php

namespace App\Services;

class AsteriskAmiService
{
    protected $host;
    protected $port;
    protected $username;
    protected $secret;

    public function __construct()
    {
        $this->host = config('services.asterisk.ami_host', '127.0.0.1');
        $this->port = config('services.asterisk.ami_port', '5038');
        $this->username = config('services.asterisk.ami_username', 'magnus');
        $this->secret = config('services.asterisk.ami_secret', 'magnussolution');
    }

    /**
     * Reload Asterisk configurations via AMI or Shell as fallback
     */
    public function reloadSip()
    {
        return $this->sendCommand('sip reload');
    }

    public function reloadDialplan()
    {
        return $this->sendCommand('dialplan reload');
    }

    protected function sendCommand($command)
    {
        // For now, implementing as a shell fallback if AMI is not connected
        // In production, we should use a proper AMI client like PAMI
        $safeCommand = escapeshellarg($command);
        return shell_exec("asterisk -rx $safeCommand");
    }
}
