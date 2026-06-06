<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Play extends Model
{
    protected $fillable = [
        'song_isrc',
        'seconds_played',
    ];

    public function song()
    {
        return $this->belongsTo(Song::class, 'song_isrc', 'isrc');
    }
}
