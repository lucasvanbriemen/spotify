<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('plays', function (Blueprint $table) {
            $table->id();
            $table->timestamps();

            $table->string('song_isrc');
            $table->foreign('song_isrc')->references('isrc')->on('songs')->onDelete('cascade');

            // How long we actually listened to the song, in seconds. This can be shorter than the song duration when we skip it, or longer when we scrub back.
            $table->integer('seconds_played');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('plays');
    }
};
