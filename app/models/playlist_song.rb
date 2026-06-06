class PlaylistSong < ApplicationRecord
  belongs_to :playlist
  belongs_to :song, foreign_key: :song_isrc, inverse_of: :playlist_songs
end
