<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\Process\Process;

class SpotifyController extends Controller
{
    public function getMp3Url(Request $request): JsonResponse
    {
        $id = $request->query('id');

        $publicRoot = storage_path('app/public/audio');

        $existing = $this->findMp3($id);
        if ($existing !== null) {
            return response()->json(['stream_url' => $existing]);
        }

        $token = $this->accessToken();
        $metaData = Http::withToken($token)->get("https://api.spotify.com/v1/tracks/{$id}");
        $name = $metaData->json('name', '');
        $artist = $metaData->json('artists.0.name', '');

        $process = new Process([
            $this->bin('yt-dlp'),
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

        $produced = $this->findMp3($id);
        if ($produced === null) {
            return response()->json([
                'error' => 'yt-dlp failed',
                'detail' => trim($process->getErrorOutput() ?: $process->getOutput()),
            ], 500);
        }

        return response()->json(['stream_url' => $produced]);
    }

    public function recommendations(Request $request): JsonResponse
    {
        $seed = trim((string) $request->query('seed', ''));
        if ($seed === '') {
            return response()->json([]);
        }

        $items = Cache::remember("recommendations.{$seed}", 3600, function () use ($seed) {
            return $this->buildRecommendations($seed);
        });

        return response()->json($items);
    }

    private function buildRecommendations(string $seed): array
    {
        $token = $this->accessToken();
        if ($token === null) {
            return [];
        }

        $track = Http::withToken($token)->get("https://api.spotify.com/v1/tracks/{$seed}");
        $trackName = $track->json('name');
        $artistName = $track->json('artists.0.name');
        if (! $trackName || ! $artistName) {
            return [];
        }

        $deezerSearch = Http::get('https://api.deezer.com/search/track', [
            'q' => "{$trackName} {$artistName}",
            'limit' => 1,
        ]);
        $deezerArtistId = $deezerSearch->json('data.0.artist.id');
        if (! $deezerArtistId) {
            return [];
        }

        $related = Http::get("https://api.deezer.com/artist/{$deezerArtistId}/related", ['limit' => 10]);
        $names = collect($related->json('data', []))->pluck('name')->filter()->take(10)->values();
        if ($names->isEmpty()) {
            return [];
        }

        $responses = Http::pool(fn ($pool) => $names->map(fn ($name) =>
            $pool->withToken($token)->get('https://api.spotify.com/v1/search', [
                'q' => 'artist:"' . $name . '"',
                'type' => 'track',
                'limit' => 1,
            ])
        )->all());

        return collect($responses)
            ->flatMap(fn ($r) => $r->json('tracks.items', []) ?? [])
            ->filter(fn ($t) => ($t['id'] ?? null) !== null && $t['id'] !== $seed)
            ->unique('id')
            ->map(fn ($track) => [
                'id' => $track['id'],
                'title' => $track['name'] ?? '',
                'artist' => collect($track['artists'] ?? [])->pluck('name')->implode(', '),
                'album' => $track['album']['name'] ?? '',
                'thumbnail' => $track['album']['images'][1]['url']
                    ?? $track['album']['images'][0]['url']
                    ?? null,
                'duration' => isset($track['duration_ms']) ? (int) round($track['duration_ms'] / 1000) : null,
            ])
            ->shuffle()
            ->values()
            ->all();
    }

    public function search(Request $request): JsonResponse
    {
        $query = trim((string) $request->query('q', ''));
        if ($query === '') {
            return response()->json([]);
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
            'id' => $track['id'] ?? null,
            'title' => $track['name'] ?? '',
            'artist' => collect($track['artists'] ?? [])->pluck('name')->implode(', '),
            'album' => $track['album']['name'] ?? '',
            'thumbnail' => $track['album']['images'][1]['url']
                ?? $track['album']['images'][0]['url']
                ?? null,
            'duration' => isset($track['duration_ms']) ? (int) round($track['duration_ms'] / 1000) : null,
            'uri' => $track['uri'] ?? null,
        ])->filter(fn ($i) => $i['id'] !== null)->values();

        return response()->json($items);
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

    public function streamMp3(Request $request, string $id): BinaryFileResponse
    {
        $path = storage_path("app/public/audio/{$id}.mp3");
        abort_unless(@is_file($path), 404);

        $response = new BinaryFileResponse($path);
        $response->headers->set('Content-Type', 'audio/mpeg');
        $response->headers->set('Accept-Ranges', 'bytes');
        $response->setAutoEtag();
        $response->setAutoLastModified();
        $response->prepare($request);

        return $response;
    }

    private function findMp3($id)
    {
        if (@is_file(storage_path("app/public/audio/{$id}.mp3"))) {
            return route('stream-mp3', ['id' => $id]);
        }

        return null;
    }

    private function bin($name)
    {
        return base_path('bin/' . $name . (PHP_OS_FAMILY === 'Windows' ? '.exe' : ''));
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
        if (PHP_OS_FAMILY === 'Windows') {
            $env['SystemRoot'] = getenv('SystemRoot') ?: 'C:\\Windows';
            $env['PATH'] = getenv('PATH') ?: 'C:\\Windows\\System32;C:\\Windows';
            $env['USERPROFILE'] = getenv('USERPROFILE') ?: '';
        }

        return $env;
    }
}
