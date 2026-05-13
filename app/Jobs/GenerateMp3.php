<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Symfony\Component\Process\Process;

class GenerateMp3 implements ShouldQueue, ShouldBeUnique
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $timeout = 240;

    public int $uniqueFor = 600;

    public function __construct(
        public string $songId,
        public string $artist,
        public string $title,
    ) {}

    public function uniqueId(): string
    {
        return $this->songId;
    }

    public function handle(): void
    {
        $publicRoot = storage_path('app/public/audio');
        if (@is_file("{$publicRoot}/{$this->songId}.mp3")) {
            return;
        }

        $tmpDir = storage_path('app/tmp');
        if (! is_dir($tmpDir)) {
            @mkdir($tmpDir, 0775, true);
        }

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
            '--output', "{$publicRoot}/{$this->songId}",
            "ytsearch5: {$this->artist} {$this->title} audio",
        ], null, [
            'TMP' => $tmpDir,
            'TEMP' => $tmpDir,
            'TMPDIR' => $tmpDir,
        ]);
        $process->setTimeout(180);
        $process->run();
    }
}
