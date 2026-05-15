<?php

namespace App\Http\Controllers;

use App\Helpers\DeezerHelper;
use App\Models\Playlist;
use App\Models\Song;
use Illuminate\Http\Request;

class PlaylistController extends Controller
{
    public function index()
    {
        $playlists = Playlist::all();

        // Change the playlists id's to be strings and add a prefix to them so we can easily distinguish them from the deezer playlists on the frontend
        $playlists = $playlists->map(function ($playlist) {
            $playlist->id = "local_{$playlist->id}";
            return $playlist;
        });

        return response()->json($playlists);
    }

    public function show(string $playlist)
    {
        if (str_starts_with($playlist, "local_")) {
            return $this->showLocal($playlist);
        } else {
            return $this->showDeezer($playlist);
        }
    }

    private function showLocal(string $playlist) {
        $id = str_replace("local_", "", $playlist);
        $playlist = Playlist::where("id", $id)->firstOrFail();

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

    private function showDeezer(string $playlist) {
        $id = str_replace("deezer_", "", $playlist);
        $deezerPlaylist = DeezerHelper::getPlaylistDetails($id);

        $allPlaylists = Playlist::with('songs')->get();

        $songs = collect($deezerPlaylist['tracks']['data'])->map(function ($track) use ($allPlaylists) {
            $isrc = $track['isrc'];

            $map = [];
            foreach ($allPlaylists as $p) {
                $map[$p->id] = [
                    'name' => $p->name,
                    'image_url' => $p->image_url,
                    'contains' => $p->songs->contains('isrc', $isrc),
                ];
            }

            return [
                'isrc' => $isrc,
                'title' => $track['title'],
                'artist' => $track['artist']['name'],
                'album' => $track['album']['title'],
                'image_url' => $track['album']['cover_medium'],
                'duration' => $track['duration'],
                'is_in_playlist_map' => $map,
            ];
        });

        return response()->json([
            'id' => "deezer_{$deezerPlaylist['id']}",
            'name' => $deezerPlaylist['title'] ?? '',
            'image_url' => $deezerPlaylist['picture_medium'] ?? '',
            'songs' => $songs,
        ]);
    }

    public function addSong(Request $request, Playlist $playlist)
    {
        $data = $request->all();

        $songDetails = DeezerHelper::getTrackDetails($data['isrc']);

        $song = Song::updateOrCreate(
            ['isrc' => $data['isrc']],
            [
                'title' => $songDetails['title'] ?? '',
                'artist' => $songDetails['artist']['name'] ?? '',
                'album' => $songDetails['album']['title'] ?? '',
                'image_url' => $songDetails['album']['cover_medium'] ?? '',
                'duration' => $songDetails['duration'] ?? 0,
            ]
        );

        $playlist->songs()->syncWithoutDetaching($song->isrc);

        return response()->json($song);
    }
}
