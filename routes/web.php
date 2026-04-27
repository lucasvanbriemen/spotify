<?php

use App\Http\Controllers\SpotifyAuthController;
use Illuminate\Support\Facades\Route;

Route::get('/auth/spotify', [SpotifyAuthController::class, 'redirect']);
Route::get('/auth/spotify/callback', [SpotifyAuthController::class, 'callback']);
Route::get('/auth/spotify/logout', [SpotifyAuthController::class, 'logout']);

Route::get('{any}', function () {
    return view('index');
})->where('any', '.*')->name('spa.catchall');
