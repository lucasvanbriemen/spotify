require "test_helper"

class TalkAudioTest < ActiveSupport::TestCase
  test "keeps a monologue transcript unlabelled" do
    lines = [ { speaker: "host", text: "A short link." } ]

    assert_equal "A short link.", TalkAudio.send(:transcript_for, lines)
  end

  test "labels each speaker in a conversation transcript" do
    lines = [
      { speaker: "host", text: "First turn." },
      { speaker: "cohost", text: "Second turn." },
      { speaker: "host", text: "Final turn." }
    ]

    expected = "Host: First turn.\n\nCo-host: Second turn.\n\nHost: Final turn."
    assert_equal expected, TalkAudio.send(:transcript_for, lines)
  end
end
