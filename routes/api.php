<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Middleware\IsLoggedIn;
use Illuminate\Support\Facades\Route;

Route::middleware(IsLoggedIn::class)->group(function () {
    Route::get('/search', [SpotifyController::class, 'search'])->name('search');
    Route::get('/get-mp3', [SpotifyController::class, 'getMp3'])->name('get-mp3');
});
