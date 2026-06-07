class Song < ApplicationRecord
  # Shown when Deezer has no album cover for a track.
  PLACEHOLDER_IMAGE = "https://firstbenefits.org/wp-content/uploads/2017/10/placeholder-300x300.png"

  self.primary_key = :isrc

  has_many :playlist_songs, foreign_key: :song_isrc, inverse_of: :song, dependent: :destroy
  has_many :playlists, through: :playlist_songs
  has_many :plays, foreign_key: :song_isrc, inverse_of: :song, dependent: :destroy
end
