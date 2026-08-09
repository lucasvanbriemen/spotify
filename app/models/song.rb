class Song < ApplicationRecord
  # Shown when Deezer has no album cover for a track.
  PLACEHOLDER_IMAGE = "https://firstbenefits.org/wp-content/uploads/2017/10/placeholder-300x300.png"

  self.primary_key = :isrc

  has_many :playlist_songs, foreign_key: :song_isrc, inverse_of: :song, dependent: :destroy
  has_many :playlists, through: :playlist_songs
  has_many :plays, foreign_key: :song_isrc, inverse_of: :song, dependent: :destroy
  has_many :karaoke_scores, foreign_key: :song_isrc, inverse_of: :song, dependent: :destroy

  # Songs the enrichment backfill (EnrichSongsJob) still has to visit.
  scope :enrichment_pending, -> { where(enriched_at: nil) }

  def decade
    release_year && release_year / 10 * 10
  end
end
