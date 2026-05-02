<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Controllers\PlaylistController;
use App\Http\Middleware\IsLoggedIn;
use Illuminate\Support\Facades\Route;

Route::middleware(IsLoggedIn::class)->group(function () {
    Route::get('/search', [SpotifyController::class, 'search'])->name('search');
    Route::get('/get-mp3', [SpotifyController::class, 'getMp3'])->name('get-mp3');
    Route::get('/audio/{id}', [SpotifyController::class, 'streamMp3'])
        ->where('id', '[A-Za-z0-9]+')
        ->name('stream-mp3');

    Route::get('/playlists', [PlaylistController::class, 'index'])->name('playlists');
});
