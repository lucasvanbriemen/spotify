class CreatePlaylistSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :playlist_songs do |t|
      t.references :playlist, null: false, foreign_key: { on_delete: :cascade }
      t.string :song_isrc, null: false

      t.timestamps
    end

    add_foreign_key :playlist_songs, :songs, column: :song_isrc, primary_key: :isrc, on_delete: :cascade
    # A song can only be in a playlist once (the Laravel app used
    # syncWithoutDetaching for the same guarantee).
    add_index :playlist_songs, [ :playlist_id, :song_isrc ], unique: true
  end
end
