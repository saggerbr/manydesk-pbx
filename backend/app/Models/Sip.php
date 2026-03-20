<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Sip extends Model
{
    protected $table = 'pkg_sip';
    public $timestamps = false;

    public function user()
    {
        return $this->belongsTo(User::class, 'id_user');
    }
}
