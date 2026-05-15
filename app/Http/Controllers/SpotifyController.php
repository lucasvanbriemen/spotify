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
    public function getMp3(Request $request, string $song_id = "")
    {
        $id = $song_id;

        $publicRoot = storage_path('app/public/audio');

        if ($this->findMp3($id)) {
            return $this->returnMp3($request, $id);
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
            '--output', "{$publicRoot}/{$id}",
            "ytsearch5: {$artist} {$name} audio",
        ], null, $this->setupEnv());
        $process->setTimeout(180);
        $process->run();

        if (! $this->findMp3($id)) {
            return response()->json([
                'error' => 'yt-dlp failed',
                'detail' => trim($process->getErrorOutput() ?: $process->getOutput()),
            ], 500);
        }

        return $this->returnMp3($request, $id);
    }

    public function search(Request $request)
    {
        $tracks = collect(DeezerHelper::search($request->query('q', '')));
        $tracks = $tracks->map(function ($track) {
            $formattedTrack = [
                "id" => $track['id'],
                "isrc" => $track['isrc'],
                "title" => $track['title'],
                "artist" => $track['artist']['name'],
                "album" => $track['album']['title'],
                "image_url" => $track['album']['cover_medium'],
                "duration" => $track['duration'],
            ];    

            return $formattedTrack;
        });

        return response()->json($tracks);

        $query = trim((string) $request->query('q', ''));
        $types = array_filter(array_map('trim', explode(',', (string) $request->query('types', 'track'))));
        $includePlaylists = \in_array('playlist', $types, true);

        if ($query === '') {
            return response()->json($includePlaylists ? ['tracks' => [], 'playlists' => []] : []);
        }

        $token = $this->accessToken();
        if ($token === null) {
            return response()->json(['error' => 'Failed to obtain Spotify access token'], 500);
        }

        $response = Http::withToken($token)->get('https://api.spotify.com/v1/search', [
            'q' => $query,
            'type' => 'track',
            'limit' => 10,
        ]);

        if ($response->failed()) {
            return response()->json(['error' => $response->body()], $response->status());
        }

        $items = collect($response->json('tracks.items', []))->map(fn ($track) => [
            'id' => random_int(1,99999),
            'file_id' => $track['id'] ?? null,
            'title' => $track['name'] ?? '',
            'artist' => collect($track['artists'] ?? [])->pluck('name')->implode(', '),
            'album' => $track['album']['name'] ?? '',
            'image_url' => $track['album']['images'][1]['url']
                ?? $track['album']['images'][0]['url']
                ?? null,
            'duration' => round((int) $track['duration_ms'] / 1000, 0),
        ])->filter(fn ($i) => $i['id'] !== null)->values();

        $allPlaylists = Playlist::with('songs')->get();

        $fileIds = $items->pluck('file_id')->filter()->all();
        $songsByFileId = Song::whereIn('file_id', $fileIds, 'and', false)->get()->keyBy('file_id');

        $items = $items->map(function ($item) use ($allPlaylists, $songsByFileId) {
            $song = $songsByFileId->get($item['file_id']);

            $item['is_in_playlist_map'] = [];
            foreach ($allPlaylists as $playlist) {
                $item['is_in_playlist_map'][$playlist->id] = [
                    'name' => $playlist->name,
                    'image_url' => $playlist->image_url,
                    'contains' => $song ? $playlist->songs->contains($song) : false,
                ];
            }

            return $item;
        });

        if (! $includePlaylists) {
            return response()->json($items);
        }

        $deezerResponse = Http::get('https://api.deezer.com/search/playlist', [
            'q' => $query,
            'limit' => 10,
        ]);

        $playlists = collect($deezerResponse->json('data', []))
            ->map(fn ($playlist) => [
                'id' => isset($playlist['id']) ? (string) $playlist['id'] : null,
                'name' => $playlist['title'] ?? '',
                'description' => '',
                'image_url' => $playlist['picture_medium'] ?? $playlist['picture'] ?? null,
                'owner' => $playlist['user']['name'] ?? '',
                'track_count' => $playlist['nb_tracks'] ?? 0,
            ])
            ->filter(fn ($p) => $p['id'] !== null)
            ->values();

        return response()->json([
            'tracks' => $items,
            'playlists' => $playlists,
        ]);
    }

    public function showDeezerPlaylist(string $playlist_id): JsonResponse
    {
        $response = Http::get("https://api.deezer.com/playlist/{$playlist_id}");

        if ($response->failed() || $response->json('error')) {
            return response()->json(['error' => $response->json('error.message', 'Playlist not found')], 404);
        }

        $songs = collect($response->json('tracks.data', []))
            ->filter(fn ($track) => isset($track['id']))
            ->map(fn ($track) => [
                'id' => random_int(1, 99999),
                'file_id' => (string) $track['id'],
                'title' => $track['title'] ?? '',
                'artist' => $track['artist']['name'] ?? '',
                'album' => $track['album']['title'] ?? '',
                'image_url' => $track['album']['cover_medium']
                    ?? $track['album']['cover'] ?? null,
                'duration' => (int) ($track['duration'] ?? 0),
            ])
            ->values();

        return response()->json([
            'id' => (string) $response->json('id'),
            'name' => $response->json('title', ''),
            'description' => $response->json('description', ''),
            'image_url' => $response->json('picture_big')
                ?? $response->json('picture_medium'),
            'owner' => $response->json('creator.name', ''),
            'songs' => $songs,
        ]);
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

    private function accessToken(): ?string
    {
        return Cache::remember('spotify.client_credentials_token', 3000, function () {
            $response = Http::asForm()
                ->withBasicAuth(
                    config('services.spotify.client_id'),
                    config('services.spotify.client_secret'),
                )
                ->post('https://accounts.spotify.com/api/token', [
                    'grant_type' => 'client_credentials',
                ]);

            if ($response->failed()) {
                return null;
            }

            return $response->json('access_token');
        });
    }

    public function returnMp3 ($response, $id): BinaryFileResponse
    {
        $path = storage_path("app/public/audio/{$id}.mp3");
        abort_unless(@is_file($path), 404);

        $response = new BinaryFileResponse($path);
        $response->headers->set('Content-Type', 'audio/mpeg');
        $response->headers->set('Accept-Ranges', 'bytes');
        $response->setAutoEtag();
        $response->setAutoLastModified();
        $response->prepare(request());

        return $response;
    }

    private function findMp3($id): bool
    {
        return @is_file(storage_path("app/public/audio/{$id}.mp3"));
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
