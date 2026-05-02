<?php

use Illuminate\Support\Facades\Route;
use App\Http\Middleware\IsLoggedIn;

Route::get('{any}', function () {
    return view('index');
})->where('any', '.*')->name('spa.catchall')->middleware(IsLoggedIn::class);
