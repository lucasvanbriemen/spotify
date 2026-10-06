# The all-in-one app shares this database and renamed the song key columns
# (songs.isrc -> songs.id, every song_isrc -> song_id) with its own
# db/music_migrate/20260921120000_key_songs_by_youtube_id.rb, then added
# songs.is_liked. Production already has those changes; this migration exists
# so fresh development and test databases end up with the same shape, and so
# schema.rb can say what the table really looks like. Every step checks the
# column first, so running it on the already-migrated database is a no-op.
class KeySongsById < ActiveRecord::Migration[8.0]
  RENAMES = {
    songs: [ :isrc, :id ],
    plays: [ :song_isrc, :song_id ],
    playlist_songs: [ :song_isrc, :song_id ],
    karaoke_scores: [ :song_isrc, :song_id ],
    karaoke_queue_items: [ :song_isrc, :song_id ]
  }.freeze

  def up
    RENAMES.each do |table, (from, to)|
      rename_column table, from, to if column_exists?(table, from) && !column_exists?(table, to)
    end

    add_column :songs, :is_liked, :boolean, default: false, null: false unless column_exists?(:songs, :is_liked)
  end

  def down
    remove_column :songs, :is_liked if column_exists?(:songs, :is_liked)

    RENAMES.each do |table, (from, to)|
      rename_column table, to, from if column_exists?(table, to) && !column_exists?(table, from)
    end
  end
end
