<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Controllers\PlaylistController;
use App\Http\Middleware\IsLoggedIn;
use Illuminate\Support\Facades\Route;

Route::middleware(IsLoggedIn::class)->group(function () {
    Route::get('/search', [SpotifyController::class, 'search'])->name('search');
    Route::get('/deezer-playlist/{playlist_id}', [SpotifyController::class, 'showDeezerPlaylist'])->name('deezer-playlist.show');
    Route::get('/get-mp3/{song_id}', [SpotifyController::class, 'getMp3'])->name('get-mp3-url');

    Route::get('/playlists', [PlaylistController::class, 'index'])->name('playlists');

    Route::get('song/{song}/lyrics', [SpotifyController::class, 'getLyrics'])->name('song.lyrics');

    Route::get('/playlist/{playlist}', [PlaylistController::class, 'show'])->name('playlist.show');
    Route::post('/playlist/{playlist}/songs', [PlaylistController::class, 'addSong'])->name('playlist.songs.store');
});
