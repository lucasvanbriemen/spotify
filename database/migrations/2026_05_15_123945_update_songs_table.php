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
        // We want to drop the file_id and the normal id from songs and replace it with isrc, which is a unique identifier for songs. This way we can easily check if a song is already in the database and we can also easily get the metadata for a song from the Spotify API using the ISRC.
        Schema::table('playlist_songs', function (Blueprint $table) {
            $table->dropForeign(['song_id']);
            $table->dropColumn('song_id');
        });

        Schema::table('songs', function (Blueprint $table) {
            $table->dropColumn(['id', 'file_id']);
            $table->string('isrc')->primary();
        });

        Schema::table('playlist_songs', function (Blueprint $table) {
            $table->string('song_isrc')->after('id');
            $table->foreign('song_isrc')->references('isrc')->on('songs')->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        //
    }
};
