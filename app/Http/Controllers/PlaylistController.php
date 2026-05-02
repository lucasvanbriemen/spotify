<?php

namespace App\Http\Controllers;

use App\Models\Playlist;

class PlaylistController extends Controller
{
    public function index()
    {
        $playlists = Playlist::all();
        return response()->json($playlists);
    }
}
