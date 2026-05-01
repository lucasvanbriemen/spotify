<?php

use App\Http\Controllers\SpotifyController;
use App\Http\Controllers\YouTubeController;
use Illuminate\Support\Facades\Route;

Route::middleware('web')->get('/search', [SpotifyController::class, 'search'])->name('search');
Route::middleware('web')->get('/get-mp3', [SpotifyController::class, 'getMp3'])->name('get-mp3');
