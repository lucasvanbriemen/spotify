<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Song extends Model
{
    protected $fillable = [
        'title',
        'artist',
        'album',
        'image_url',
        'duration',
        'isrc',
    ];

    public function playlists()
    {
        return $this->belongsToMany(Playlist::class, 'playlist_songs')->withTimestamps();
    }
}
