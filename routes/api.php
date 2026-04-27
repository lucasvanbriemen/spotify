<?php

use App\Http\Controllers\SpotifyAuthController;
use Illuminate\Support\Facades\Route;

Route::middleware('web')->get('/spotify/token', [SpotifyAuthController::class, 'token'])->name('spotify.token');
