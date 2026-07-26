require "test_helper"

class TalkScriptsTest < ActiveSupport::TestCase
  test "parses an exact three-turn host exchange" do
    text = <<~SCRIPT
      HOST: That was a good one to let breathe.
      COHOST: Just for a second. This next record changes the temperature.
      HOST: Here is the next one.
    SCRIPT

    lines = TalkScripts.send(:parse_dialogue, text)

    assert_equal %w[host cohost host], lines.pluck(:speaker)
    assert_equal "That was a good one to let breathe.", lines.first.fetch(:text)
  end

  test "rejects malformed host exchanges" do
    assert_raises(Openai::Client::Error) do
      TalkScripts.send(:parse_dialogue, "HOST: One line is not a conversation.")
    end
  end

  test "normalizes a monologue to the main host" do
    lines = TalkScripts.send(:normalize_lines, "A short radio link.")

    assert_equal [ { speaker: "host", text: "A short radio link." } ], lines
  end

  test "requires both title and artist when validating a host turn" do
    song = Struct.new(:title, :artist).new("Night Drive", "The Signals")

    assert TalkScripts.send(:song_named?, "That was Night Drive by The Signals.", song)
    assert_not TalkScripts.send(:song_named?, "That was the last track by The Signals.", song)
  end
end
