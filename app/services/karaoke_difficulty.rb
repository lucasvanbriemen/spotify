# Summarizes a song's quantized melody (notes.json) into something the search
# screen can show as a badge. Baked into the karaoke manifest at separation
# time rather than derived on read: status is polled and search annotates every
# result, so a small manifest read beats re-parsing a note list each time.
module KaraokeDifficulty
  # A narrow range sung slowly is a singalong; a wide range, a fast line rate,
  # or notes held for several seconds all mean the song is asking for something.
  EASY_MAX_RANGE = 12
  EASY_MAX_NOTES_PER_SECOND = 1.5
  HARD_MIN_RANGE = 20
  HARD_MIN_NOTES_PER_SECOND = 2.8
  HARD_MIN_LONGEST_NOTE = 4.0

  class << self
    # notes_json is the parsed notes.json (string keys). Returns nil when
    # there's no melody to describe — instrumentals, rap, anything pyin
    # couldn't track — which the client renders as no badge at all.
    def summary(notes_json)
      notes = notes_json && notes_json["notes"]
      return nil if notes.blank?

      span = notes.map { |note| note["end"].to_f }.max - notes.map { |note| note["start"].to_f }.min
      range = notes_json["midi_max"].to_i - notes_json["midi_min"].to_i
      longest = notes.map { |note| note["end"].to_f - note["start"].to_f }.max
      notes_per_second = span.positive? ? notes.size / span : 0.0

      {
        "level" => level(range, notes_per_second, longest),
        "range_semitones" => range,
        "notes_per_second" => notes_per_second.round(2),
        "longest_note_seconds" => longest.round(2)
      }
    end

    private

    def level(range, notes_per_second, longest)
      if range >= HARD_MIN_RANGE || notes_per_second >= HARD_MIN_NOTES_PER_SECOND || longest >= HARD_MIN_LONGEST_NOTE
        "hard"
      elsif range <= EASY_MAX_RANGE && notes_per_second <= EASY_MAX_NOTES_PER_SECOND
        "easy"
      else
        "medium"
      end
    end
  end
end
