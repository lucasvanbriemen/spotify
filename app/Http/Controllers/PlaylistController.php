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
        $playlist->load('songs');
        $allPlaylists = Playlist::with('songs')->get();

        $playlist->setRelation('songs', $playlist->songs->map(function ($song) use ($allPlaylists) {
            $map = [];
            foreach ($allPlaylists as $p) {
                $map[$p->id] = [
                    'name' => $p->name,
                    'image_url' => $p->image_url,
                    'contains' => $p->songs->contains($song),
                ];
            }
            $song->setAttribute('is_in_playlist_map', $map);
            return $song;
        }));

        return response()->json($playlist);
    }

    public function addSong(Request $request, Playlist $playlist)
    {
        $data = $request->all();

        $song = Song::updateOrCreate(
            ['isrc' => $data['spotify_id']],
            [
                'title' => $data['title'] ?? '',
                'artist' => $data['artist'] ?? '',
                'album' => $data['album'] ?? '',
                'image_url' => $data['image_url'] ?? '',
                'duration' => $data['duration'] ?? 0,
            ]
        );

        $playlist->songs()->syncWithoutDetaching($song->isrc);

        return response()->json($song);
    }
}
