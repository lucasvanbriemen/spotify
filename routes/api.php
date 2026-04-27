<?php

use App\Http\Controllers\SpotifyAuthController;
use Illuminate\Support\Facades\Route;

Route::get('/spotify/token', [SpotifyAuthController::class, 'token']);
