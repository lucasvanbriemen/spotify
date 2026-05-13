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
        'file_id',
    ];

    protected $appends = [
        'name',
        'mp3_url',
        'duration_ms',
    ];

    public function playlists()
    {
        return $this->belongsToMany(Playlist::class, 'playlist_songs')->withTimestamps();
    }

    public function getNameAttribute(): ?string
    {
        return $this->title;
    }

    public function getMp3UrlAttribute(): ?string
    {
        return $this->file_id;
    }

    public function getDurationMsAttribute(): ?int
    {
        return $this->duration;
    }
}
