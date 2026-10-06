class Play < ApplicationRecord
  # belongs_to is required by default, which also enforces that the ISRC
  # exists in songs (the Laravel app validated exists:songs,isrc).
  alias_attribute :song_isrc, :song_id

  belongs_to :song, foreign_key: :song_id, inverse_of: :plays

  validates :seconds_played, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
end
