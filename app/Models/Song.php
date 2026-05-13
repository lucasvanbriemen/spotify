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

    public function playlist()
    {
        return $this->belongsTo(Playlist::class);
    }
}
