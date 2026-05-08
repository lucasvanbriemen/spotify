<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Controllers\PlaylistController;
use App\Http\Middleware\IsLoggedIn;
use Illuminate\Support\Facades\Route;

Route::middleware(IsLoggedIn::class)->group(function () {
    Route::get('/search', [SpotifyController::class, 'search'])->name('search');
    Route::get('/recommendations', [SpotifyController::class, 'recommendations'])->name('recommendations');
    Route::get('/get-mp3-url', [SpotifyController::class, 'getMp3Url'])->name('get-mp3-url');
    Route::get('/audio/{id}', [SpotifyController::class, 'streamMp3'])->name('stream-mp3');

    Route::get('/playlists', [PlaylistController::class, 'index'])->name('playlists');

    Route::get('/playlist/{playlist}', [PlaylistController::class, 'show'])->name('playlist.show');
    Route::post('/playlist/{playlist}/songs', [PlaylistController::class, 'addSong'])->name('playlist.songs.store');
});
