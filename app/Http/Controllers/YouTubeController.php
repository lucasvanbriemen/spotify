<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Symfony\Component\Process\Process;

class YouTubeController extends Controller
{
    public function audio(Request $request): JsonResponse
    {
        $id = trim((string) $request->query('id', ''));
        if (! preg_match('/^[A-Za-z0-9_-]{11}$/', $id)) {
            return response()->json(['error' => 'Invalid video id'], 422);
        }

        $temp = sys_get_temp_dir();
        $process = new Process(
            [
                config('services.youtube.yt_dlp_path'),
                '-f', 'bestaudio',
                '-g',
                "https://www.youtube.com/watch?v={$id}",
            ],
            null,
            [
                'TEMP' => $temp,
                'TMP' => $temp,
                'USERPROFILE' => $_SERVER['USERPROFILE'] ?? getenv('USERPROFILE'),
                'APPDATA' => $_SERVER['APPDATA'] ?? getenv('APPDATA'),
                'LOCALAPPDATA' => $_SERVER['LOCALAPPDATA'] ?? getenv('LOCALAPPDATA'),
                'SYSTEMROOT' => $_SERVER['SYSTEMROOT'] ?? getenv('SYSTEMROOT'),
                'PATH' => $_SERVER['PATH'] ?? getenv('PATH'),
            ]
        );
        $process->setTimeout(30);
        $process->run();

        if (! $process->isSuccessful()) {
            return response()->json([
                'error' => 'yt-dlp failed',
                'detail' => trim($process->getErrorOutput() ?: $process->getOutput()),
            ], 500);
        }

        $url = trim($process->getOutput());
        if ($url === '') {
            return response()->json(['error' => 'No audio stream found'], 404);
        }

        return response()->json(['stream_url' => $url]);
    }
}
