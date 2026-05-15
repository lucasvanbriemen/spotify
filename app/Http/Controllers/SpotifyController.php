<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\Process\Process;
use App\Models\Song;
use App\Models\Playlist;
use App\Helpers\DeezerHelper;

class SpotifyController extends Controller
{
    public function getMp3(Request $request, string $isrc = "")
    {
        $publicRoot = storage_path('app/public/audio');

        if (Song::where('isrc', '=', $isrc, true)->exists()) {
            return $this->returnMp3($request, $isrc);
        }

        $name = trim((string) $request->query('title', ''));
        $artist = trim((string) $request->query('artist', ''));

        $process = new Process([
            base_path('bin/yt-dlp'),
            '--no-playlist',
            '--extract-audio',
            '--audio-format', 'mp3',
            '--audio-quality', '0',
            '--restrict-filenames',
            '--no-progress',
            '--match-filter', 'age_limit<18',
            '--max-downloads', '1',
            '--ffmpeg-location', base_path('bin'),
            '--output', "{$publicRoot}/{$isrc}",
            "ytsearch5: {$artist} {$name} audio",
        ], null, $this->setupEnv());
        $process->setTimeout(180);
        $process->run();

        Song::create([
            'isrc' => $isrc,
            'title' => $name,
            'artist' => $artist,
            'album' => '',
            'duration' => 0,
        ]);

        return $this->returnMp3($request, $isrc);
    }

    public function search(Request $request)
    {
        $tracks = collect(DeezerHelper::search($request->query('q', '')));
        $tracks = $tracks->map(function ($track) {
            $formattedTrack = [
                "isrc" => $track['isrc'],
                "title" => $track['title'],
                "artist" => $track['artist']['name'],
                "album" => $track['album']['title'],
                "image_url" => $track['album']['cover_medium'],
                "duration" => $track['duration'],
            ];    

            return $formattedTrack;
        });


        $allPlaylists = Playlist::with('songs')->get();

        $isrcs = $tracks->pluck('isrc')->filter()->all();
        $songsByIsrc = Song::whereIn('isrc', $isrcs)->get()->keyBy('isrc');

        $tracks = $tracks->map(function ($track) use ($allPlaylists, $songsByIsrc) {
            $song = $songsByIsrc->get($track['isrc']);

            $track['is_in_playlist_map'] = [];
            foreach ($allPlaylists as $playlist) {
                $track['is_in_playlist_map'][$playlist->id] = [
                    'name' => $playlist->name,
                    'image_url' => $playlist->image_url,
                    'contains' => $song ? $playlist->songs->contains($song) : false,
                ];
            }

            return $track;
        });

        return response()->json($tracks);
    }

    public function getLyrics(Song $song)
    {
        //https://lrclib.net/docs
        $url = "https://lrclib.net/api/get?artist_name=" . urlencode($song->artist) . "&track_name=" . urlencode($song->title) ."&album_name=" . urlencode($song->album) . "&durration=" . $song->duration;

        $response = Http::get($url);

        $response = json_decode($response, true);

        if (!isset($response["plainLyrics"]) && !isset($response["syncedLyrics"])) {
            return response()->json(['error' => 'Lyrics not found'], 404);
        }

        return $response;
    }

    public function returnMp3 ($response, $isrc): BinaryFileResponse
    {
        $path = storage_path("app/public/audio/{$isrc}.mp3");
        abort_unless(@is_file($path), 404);

        $response = new BinaryFileResponse($path);
        $response->headers->set('Content-Type', 'audio/mpeg');
        $response->headers->set('Accept-Ranges', 'bytes');
        $response->setAutoEtag();
        $response->setAutoLastModified();
        $response->prepare(request());

        return $response;
    }

    private function setupEnv() {
        $tmpDir = storage_path('app/tmp');
        if (! is_dir($tmpDir)) {
            @mkdir($tmpDir, 0775, true);
        }

        $env = [
            'TMP' => $tmpDir,
            'TEMP' => $tmpDir,
            'TMPDIR' => $tmpDir,
        ];

        return $env;
    }
}
