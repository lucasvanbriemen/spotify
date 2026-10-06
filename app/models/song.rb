class Song < ApplicationRecord
  # Shown when Deezer has no album cover for a track.
  PLACEHOLDER_IMAGE = "https://firstbenefits.org/wp-content/uploads/2017/10/placeholder-300x300.png"

  # The key column was renamed from `isrc` to `id` (and every `song_isrc` to
  # `song_id`) by the all-in-one app, which shares this database and now keys
  # new songs by YouTube video id. This app still speaks "isrc" everywhere —
  # its routes, its JSON, its artifact directories — so the old name stays as
  # an alias and the value is simply whatever string identifies the song.
  alias_attribute :isrc, :id

  has_many :playlist_songs, foreign_key: :song_id, inverse_of: :song, dependent: :destroy
  has_many :playlists, through: :playlist_songs
  has_many :plays, foreign_key: :song_id, inverse_of: :song, dependent: :destroy
  has_many :karaoke_scores, foreign_key: :song_id, inverse_of: :song, dependent: :destroy

  # Songs the enrichment backfill (EnrichSongsJob) still has to visit.
  scope :enrichment_pending, -> { where(enriched_at: nil) }

  def decade
    release_year && release_year / 10 * 10
  end
end
