require "test_helper"
require "minitest/mock"

class TtsClientTest < ActiveSupport::TestCase
  test "directs Dutch intros like a live music-radio link" do
    request = nil

    Tts::Providers::Openai.stub(:synthesize, ->(**args) { request = args; "mp3" }) do
      assert_equal "mp3", Tts::Client.synthesize(
        text: "Een korte link.",
        language: "nl",
        kind: "intro"
      )
    end

    assert_equal ENV.fetch("TTS_VOICE_NL", "cedar"), request[:voice]
    assert_includes request[:instructions], "professionele radiostudio"
    assert_includes request[:instructions], "ontspannen muziekradio-link"
    assert_not_includes request[:instructions], "radiojournaal"
  end

  test "uses a distinct composed delivery for English news" do
    request = nil

    Tts::Providers::Openai.stub(:synthesize, ->(**args) { request = args; "mp3" }) do
      Tts::Client.synthesize(text: "The news.", language: "en", kind: "news")
    end

    assert_includes request[:instructions], "professional radio studio"
    assert_includes request[:instructions], "radio news bulletin"
    assert_includes request[:instructions], "Avoid melodrama"
  end
end
