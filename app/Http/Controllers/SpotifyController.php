<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Symfony\Component\Process\Process;

class SpotifyController extends Controller
{
    public function getMp3(Request $request): JsonResponse
    {
        $id = $request->query('id');

        $publicRoot = storage_path('app/public/audio');
        $trackDir = "{$publicRoot}/{$id}";
        if (! is_dir($trackDir) && ! @mkdir($trackDir, 0775, true) && ! is_dir($trackDir)) {
            return response()->json(['error' => 'Could not create output directory'], 500);
        }

        $existing = $this->findMp3($trackDir);
        if ($existing !== null) {
            return response()->json(['stream_url' => $this->publicUrl($publicRoot, $existing)]);
        }

        $token = $this->accessToken();
        $meta = Http::withToken($token)->get("https://api.spotify.com/v1/tracks/{$id}");
        $name = (string) $meta->json('name', '');
        $artist = (string) $meta->json('artists.0.name', '');
        $query = trim($artist.' '.$name);

        $temp = sys_get_temp_dir();
        $path = $this->resolvedPath();
        $args = [
            config('services.youtube.yt_dlp_path', 'yt-dlp'),
            '--no-playlist',
            '--extract-audio',
            '--audio-format', 'mp3',
            '--audio-quality', '0',
            '--restrict-filenames',
            '--no-progress',
            '-o', $trackDir.DIRECTORY_SEPARATOR.'%(title)s.%(ext)s',
        ];
        $ffmpeg = $this->findExecutable('ffmpeg', $path);
        if ($ffmpeg !== null) {
            $args[] = '--ffmpeg-location';
            $args[] = dirname($ffmpeg);
        }
        $args[] = "ytsearch1:{$query} audio";

        $process = new Process(
            $args,
            null,
            [
                'TEMP' => $temp,
                'TMP' => $temp,
                'USERPROFILE' => $_SERVER['USERPROFILE'] ?? getenv('USERPROFILE'),
                'APPDATA' => $_SERVER['APPDATA'] ?? getenv('APPDATA'),
                'LOCALAPPDATA' => $_SERVER['LOCALAPPDATA'] ?? getenv('LOCALAPPDATA'),
                'SYSTEMROOT' => $_SERVER['SYSTEMROOT'] ?? getenv('SYSTEMROOT'),
                'PATH' => $path,
            ]
        );
        $process->setTimeout(180);
        $process->run();

        if (! $process->isSuccessful()) {
            return response()->json([
                'error' => 'yt-dlp failed',
                'detail' => trim($process->getErrorOutput() ?: $process->getOutput()),
            ], 500);
        }

        $produced = $this->findMp3($trackDir);
        if ($produced === null) {
            return response()->json(['error' => 'No audio file produced'], 500);
        }

        return response()->json(['stream_url' => $this->publicUrl($publicRoot, $produced)]);
    }

    private function findMp3(string $dir): ?string
    {
        if (! is_dir($dir)) {
            return null;
        }
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($dir, \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $file) {
            if ($file->isFile() && strtolower($file->getExtension()) === 'mp3') {
                return $file->getPathname();
            }
        }
        return null;
    }

    private function publicUrl(string $publicRoot, string $absolutePath): string
    {
        $relative = ltrim(str_replace('\\', '/', substr($absolutePath, strlen($publicRoot))), '/');
        $segments = array_map('rawurlencode', explode('/', $relative));
        return asset('storage/audio/'.implode('/', $segments));
    }

    private function findExecutable(string $name, string $path): ?string
    {
        $isWin = PHP_OS_FAMILY === 'Windows';
        $separator = $isWin ? ';' : ':';
        $exts = $isWin ? ['.exe', '.cmd', '.bat', ''] : [''];
        foreach (explode($separator, $path) as $dir) {
            $dir = trim($dir, " \t\"");
            if ($dir === '') {
                continue;
            }
            foreach ($exts as $ext) {
                $candidate = $dir.DIRECTORY_SEPARATOR.$name.$ext;
                if (@is_file($candidate)) {
                    return $candidate;
                }
            }
        }
        if ($isWin && $name === 'ffmpeg') {
            $glob = glob(($_SERVER['LOCALAPPDATA'] ?? getenv('LOCALAPPDATA'))
                .'\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_*\\ffmpeg-*-full_build\\bin\\ffmpeg.exe');
            if (! empty($glob)) {
                return $glob[0];
            }
        }
        return null;
    }

    private function resolvedPath(): string
    {
        $parts = [];
        $local = base_path('bin');
        if (@is_dir($local)) {
            $parts[] = $local;
        }
        if (PHP_OS_FAMILY === 'Windows') {
            foreach (['Machine', 'User'] as $scope) {
                $proc = new Process([
                    'powershell', '-NoProfile', '-Command',
                    "[Environment]::GetEnvironmentVariable('Path','{$scope}')",
                ]);
                $proc->run();
                if ($proc->isSuccessful()) {
                    $value = trim($proc->getOutput());
                    if ($value !== '') {
                        $parts[] = $value;
                    }
                }
            }
        }
        if ($current = ($_SERVER['PATH'] ?? getenv('PATH'))) {
            $parts[] = $current;
        }
        return implode(PHP_OS_FAMILY === 'Windows' ? ';' : ':', array_filter($parts));
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
}
