<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Controllers\YouTubeController;
use Illuminate\Support\Facades\Route;

Route::middleware('web')->get('/search', [SpotifyController::class, 'search'])->name('search');
Route::middleware('web')->get('/youtube/audio', [YouTubeController::class, 'audio'])->name('youtube.audio');
