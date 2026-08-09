class CreateKaraokeScores < ActiveRecord::Migration[8.0]
  def change
    # One row per singer per finished karaoke performance, mirroring plays:
    # same songs.isrc foreign key, same cascade. There is no User model (the
    # login service hands back a plain hash), so a performance is attributed by
    # the name typed on the setup screen.
    #
    # The Song row is always there by the time a score can be posted:
    # VocalSeparation calls SongCache.ensure_cached, which creates it, before a
    # song is ever singable.
    # Charset and collation are pinned rather than inherited: songs (and plays)
    # are utf8mb4_unicode_ci from the Laravel days while the database default
    # is utf8mb4_general_ci, and MySQL refuses a foreign key whose column
    # collation doesn't match the key it points at.
    create_table :karaoke_scores, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.string :singer_name, null: false
      t.string :song_isrc, null: false
      # Normalized 0..10000 so any two performances are comparable regardless
      # of how long or note-dense the song is.
      t.integer :score, null: false
      t.float :accuracy
      # Per-line detail for the results screen; never queried against.
      t.json :meta

      t.timestamps
    end

    add_foreign_key :karaoke_scores, :songs, column: :song_isrc, primary_key: :isrc, on_delete: :cascade
    # Answers both "scores for this song" (prefix) and "this singer's best on
    # this song" (MAX(score) grouped by singer) straight off the index.
    add_index :karaoke_scores, [ :song_isrc, :singer_name, :score ]
    add_index :karaoke_scores, :created_at
  end
end
