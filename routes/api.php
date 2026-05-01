<?php

use App\Http\Controllers\SpotifyAuthController;
use App\Http\Controllers\YouTubeController;
use Illuminate\Support\Facades\Route;

Route::middleware('web')->get('/spotify/token', [SpotifyAuthController::class, 'token'])->name('spotify.token');
Route::middleware('web')->get('/youtube/search', [YouTubeController::class, 'search'])->name('youtube.search');
Route::middleware('web')->get('/youtube/audio', [YouTubeController::class, 'audio'])->name('youtube.audio');
