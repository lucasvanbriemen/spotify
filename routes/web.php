<?php

use App\Http\Controllers\SpotifyAuthController;
use Illuminate\Support\Facades\Route;

Route::get('{any}', function () {
    return view('index');
})->where('any', '.*')->name('spa.catchall');
