class KaraokeScore < ApplicationRecord
  # belongs_to is required by default, which also enforces that the ISRC
  # exists in songs — same as Play.
  belongs_to :song, foreign_key: :song_isrc, inverse_of: :karaoke_scores

  # MariaDB backs json columns with longtext plus a json_valid check, which the
  # adapter reports as text — declaring the type keeps hashes round-tripping
  # (the talk_segments.meta precedent).
  attribute :meta, :json

  normalizes :singer_name, with: ->(name) { name.strip }

  validates :singer_name, presence: true, length: { maximum: 50 }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
end
