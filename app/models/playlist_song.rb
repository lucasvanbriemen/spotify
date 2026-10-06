class PlaylistSong < ApplicationRecord
  belongs_to :playlist
  alias_attribute :song_isrc, :song_id

  belongs_to :song, foreign_key: :song_id, inverse_of: :playlist_songs
end
