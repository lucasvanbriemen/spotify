<?php

namespace App\Http\Controllers;

use App\Jobs\GenerateMp3;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Symfony\Component\Process\Process;

class SpotifyController extends Controller
{
    public function getMp3(Request $request, string $song_id)
    {
        $id = $song_id;

        if ($this->findMp3($id)) {
            return $this->returnMp3($request, $id);
        }

        $token = $this->accessToken();
        $metaData = Http::withToken($token)->get("https://api.spotify.com/v1/tracks/{$id}");
        $name = $metaData->json('name', '');
        $artist = $metaData->json('artists.0.name', '');

        GenerateMp3::dispatch($id, $artist, $name);

        $process = new Process([
            base_path('bin/yt-dlp'),
            '--no-playlist',
            '--restrict-filenames',
            '--no-progress',
            '--match-filter', 'age_limit<18',
            '--format', 'bestaudio',
            '--get-url',
            "ytsearch1: {$artist} {$name} audio",
        ], null, $this->setupEnv());
        $process->setTimeout(60);
        $process->run();

        $signedUrl = trim($process->getOutput());
        if ($signedUrl === '' || ! filter_var($signedUrl, FILTER_VALIDATE_URL)) {
            return response()->json([
                'error' => 'yt-dlp failed',
                'detail' => trim($process->getErrorOutput() ?: $process->getOutput()),
            ], 500);
        }

        return new StreamedResponse(function () use ($signedUrl) {
            $ch = curl_init($signedUrl);
            curl_setopt_array($ch, [
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_WRITEFUNCTION => function ($_ch, $chunk) {
                    echo $chunk;
                    @ob_flush();
                    flush();
                    return \strlen($chunk);
                },
                CURLOPT_FAILONERROR => true,
            ]);
            curl_exec($ch);
        }, 200, [
            'Content-Type' => 'audio/webm',
            'Accept-Ranges' => 'none',
            'Cache-Control' => 'no-store',
        ]);
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
