require "test_helper"

class TalkScriptsTest < ActiveSupport::TestCase
  test "intro falls back to the static template when the LLM fails" do
    segment = intro_segment

    script = Openai::Client.stub(:complete, ->(*) { raise Openai::Client::Error, "down" }) do
      TalkScripts.build(segment)
    end

    assert_includes script, songs(:rock_0).title
    assert_includes script, songs(:rock_1).title
    assert_includes script, "Hierna"
  end

  test "intro degrades to a station id line when the songs are gone" do
    segment = TalkSegment.new(
      id: "talk-intro-cafe00000001", kind: "intro", language: "en",
      expires_at: 1.hour.from_now,
      meta: { "prev_isrc" => "GONE00000001", "next_isrc" => "GONE00000002" }
    )

    script = TalkScripts.build(segment)

    assert_equal "You're listening to LTVB Radio.", script
  end

  test "weather check is a deterministic template with a colloquial Dutch time" do
    conditions = { temperature: 21.4, description_nl: "bewolkt", description_en: "overcast" }
    segment = TalkSegment.new(
      id: "talk-weather-nl-202607260915", kind: "weather", language: "nl",
      expires_at: 1.hour.from_now,
      meta: { "airs_at" => "2026-07-26T09:15:00+02:00" }
    )

    script = Weather::Client.stub(:current, conditions) do
      TalkScripts.build(segment)
    end

    assert_includes script, "kwart over negen"
    assert_includes script, "21 graden"
    assert_includes script, "bewolkt"
  end

  test "dutch clock phrases cover the half-hour system" do
    phrases = {
      "09:00" => "negen uur",
      "09:15" => "kwart over negen",
      "09:20" => "tien voor half tien",
      "09:30" => "half tien",
      "09:45" => "kwart voor tien",
      "12:55" => "vijf voor één"
    }

    phrases.each do |clock, expected|
      time = Time.zone.parse("2026-07-26 #{clock}")
      assert_includes TalkScripts.send(:time_phrase_nl, time), expected
    end
  end

  test "news raises without headlines so the segment is marked failed" do
    segment = TalkSegment.new(
      id: "talk-news-nl-2026072609", kind: "news", language: "nl",
      expires_at: 1.day.from_now, meta: {}
    )

    assert_raises(Openai::Client::Error) { TalkScripts.build(segment) }
  end

  test "news bulletin ids pass both the model pattern and the controller gate" do
    id = "talk-news-nl-2026072609"

    assert_match TalkSegment::ID_PATTERN, id
    assert_match(/\A[a-zA-Z0-9-]+\z/, id)
  end

  private

  def intro_segment
    TalkSegment.new(
      id: "talk-intro-abc123def456", kind: "intro", language: "nl",
      expires_at: 1.hour.from_now,
      meta: { "prev_isrc" => songs(:rock_0).isrc, "next_isrc" => songs(:rock_1).isrc }
    )
  end
end
