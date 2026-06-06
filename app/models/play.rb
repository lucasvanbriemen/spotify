class Play < ApplicationRecord
  # belongs_to is required by default, which also enforces that the ISRC
  # exists in songs (the Laravel app validated exists:songs,isrc).
  belongs_to :song, foreign_key: :song_isrc, inverse_of: :plays

  validates :seconds_played, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
end
