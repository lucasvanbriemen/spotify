<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Playlist extends Model
{
    protected $fillable = [
        'name',
        'image_url',
    ];

    public function songs()
    {
        return $this->belongsToMany(Song::class, 'playlist_songs')->withTimestamps();
    }
}
