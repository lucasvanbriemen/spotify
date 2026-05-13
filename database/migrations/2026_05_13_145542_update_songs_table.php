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
        // Drop the playlist_songs row
        Schema::table("playlist_songs", function (Blueprint $table) {
            $table->dropColumn("mp3_url");
            $table->dropColumn("duration_ms");
            $table->dropColumn("name");
            $table->dropColumn("artist");
            $table->dropColumn("album");
            $table->dropColumn("image_url");

            // Add the songs id as a foreign key
            $table->unsignedBigInteger("song_id")->nullable()->after("id");
            $table->foreign("song_id")->references("id")->on("songs")->onDelete("cascade");
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
