<?php

use App\Http\Controllers\SpotifyAuthController;
use App\Http\Controllers\YouTubeController;
use Illuminate\Support\Facades\Route;

Route::middleware('web')->get('/search', [YouTubeController::class, 'search'])->name('search');
Route::middleware('web')->get('/youtube/audio', [YouTubeController::class, 'audio'])->name('youtube.audio');
