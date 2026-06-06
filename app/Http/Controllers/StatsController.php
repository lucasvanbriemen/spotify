<?php

namespace App\Http\Controllers;

use App\Models\Play;
use Illuminate\Http\Request;

class StatsController extends Controller
{
    public function storePlay(Request $request)
    {
        $data = $request->validate([
            'isrc' => ['required', 'string', 'exists:songs,isrc'],
            'seconds_played' => ['required', 'integer', 'min:1'],
        ]);

        $play = Play::create([
            'song_isrc' => $data['isrc'],
            'seconds_played' => $data['seconds_played'],
        ]);

        return response()->json($play, 201);
    }

    public function index()
    {
        $topSongs = Play::selectRaw('song_isrc, COUNT(*) as play_count, SUM(seconds_played) as seconds_played')
            ->groupBy('song_isrc')
            ->orderByDesc('play_count')
            ->limit(5)
            ->with('song')
            ->get()
            ->map(function ($play) {
                return [
                    'isrc' => $play->song_isrc,
                    'title' => $play->song->title ?? 'Unknown',
                    'artist' => $play->song->artist ?? 'Unknown Artist',
                    'image_url' => $play->song->image_url ?? null,
                    'play_count' => (int) $play->play_count,
                    'seconds_played' => (int) $play->seconds_played,
                ];
            });

        return response()->json([
            'total_plays' => Play::count(),
            'unique_songs' => Play::distinct()->count('song_isrc'),
            'total_seconds_played' => (int) Play::sum('seconds_played'),
            'top_songs' => $topSongs,
        ]);
    }
}
