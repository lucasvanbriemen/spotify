require "test_helper"

class KaraokeDifficultyTest < ActiveSupport::TestCase
  # count notes spread evenly over `seconds`, alternating between the two
  # pitches so the range is exactly midi_max - midi_min.
  def notes_json(count:, seconds:, duration: 0.5, midi_min: 60, midi_max: 67)
    step = seconds.to_f / count
    notes = Array.new(count) do |index|
      start = index * step
      { "start" => start.round(3), "end" => (start + duration).round(3), "midi" => index.even? ? midi_min : midi_max }
    end

    { "notes" => notes, "midi_min" => midi_min, "midi_max" => midi_max }
  end

  test "a narrow range sung slowly is easy" do
    summary = KaraokeDifficulty.summary(notes_json(count: 10, seconds: 20))

    assert_equal "easy", summary["level"]
    assert_equal 7, summary["range_semitones"]
    assert_in_delta 0.54, summary["notes_per_second"], 0.05
    assert_in_delta 0.5, summary["longest_note_seconds"], 0.001
  end

  test "a wide range is hard however slowly it is sung" do
    summary = KaraokeDifficulty.summary(notes_json(count: 10, seconds: 20, midi_min: 55, midi_max: 80))

    assert_equal "hard", summary["level"]
    assert_equal 25, summary["range_semitones"]
  end

  test "a fast line rate is hard however narrow the range" do
    summary = KaraokeDifficulty.summary(notes_json(count: 60, seconds: 20, duration: 0.3))

    assert_equal "hard", summary["level"]
    assert_operator summary["notes_per_second"], :>=, KaraokeDifficulty::HARD_MIN_NOTES_PER_SECOND
  end

  test "a long held note is hard on its own" do
    payload = notes_json(count: 6, seconds: 30)
    payload["notes"].last["end"] = payload["notes"].last["start"] + 5.0

    assert_equal "hard", KaraokeDifficulty.summary(payload)["level"]
  end

  test "everything in between is medium" do
    summary = KaraokeDifficulty.summary(notes_json(count: 40, seconds: 20, duration: 0.3, midi_max: 75))

    assert_equal "medium", summary["level"]
    assert_equal 15, summary["range_semitones"]
  end

  test "no melody means no badge" do
    assert_nil KaraokeDifficulty.summary(nil)
    assert_nil KaraokeDifficulty.summary({})
    assert_nil KaraokeDifficulty.summary({ "notes" => [], "midi_min" => nil, "midi_max" => nil })
  end
end
