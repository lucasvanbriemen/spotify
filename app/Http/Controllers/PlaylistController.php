<?php

namespace App\Http\Controllers;

use App\Models\Playlist;
use App\Models\Song;
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
        return response()->json($playlist->load('songs'));
    }

    public function addSong(Request $request, Playlist $playlist)
    {
        $data = $request->all();

        $song = Song::firstOrCreate(
            ['file_id' => $data['spotify_id']],
            [
                'title' => $data['name'],
                'artist' => $data['artist'],
                'album' => $data['album'],
                'image_url' => $data['image_url'],
                'duration' => $data['duration_ms'],
            ]
        );

        $playlist->songs()->attach($song->id);

        return response()->json($song);
    }
}
