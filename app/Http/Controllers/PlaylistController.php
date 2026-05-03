<?php

namespace App\Http\Controllers;

use App\Models\Playlist;
use App\Models\PlaylistSong;
use Illuminate\Http\Request;

class PlaylistController extends Controller
{
    public function index()
    {
        $playlists = Playlist::all();
        return response()->json($playlists);
    }

    public function show(Playlist $playlist)
    {
        return response()->json($playlist);
    }

    public function addSong(Request $request, Playlist $playlist)
    {
        $data = $request->all();

        $song = $playlist->songs()->create([
            'name' => $data['name'],
            'artist' => $data['artist'],
            'album' => $data['album'],
            'image_url' => $data['image_url'],
            'duration_ms' => $data['duration_ms'],
            'mp3_url' => $data['spotify_id'],
        ]);

        return response()->json($song);
    }
}
