require "test_helper"

module Tts
  class ClientTest < ActiveSupport::TestCase
    test "uses marin for the English host and cedar for the cohost" do
      with_voice_env do
        assert_equal "marin", Client.send(:voice_for, "en", "host")
        assert_equal "cedar", Client.send(:voice_for, "en", "cohost")
      end
    end

    test "allows presenter voices to be configured independently" do
      with_voice_env("TTS_VOICE_HOST" => "coral", "TTS_VOICE_COHOST" => "onyx") do
        assert_equal "coral", Client.send(:voice_for, "en", "host")
        assert_equal "onyx", Client.send(:voice_for, "en", "cohost")
      end
    end

    test "uses independent local Kokoro voices" do
      with_voice_env(
        "TTS_PROVIDER" => "kokoro",
        "KOKORO_VOICE_HOST" => "af_heart",
        "KOKORO_VOICE_COHOST" => "bf_emma"
      ) do
        assert_equal "af_heart", Client.send(:voice_for, "en", "host")
        assert_equal "bf_emma", Client.send(:voice_for, "en", "cohost")
      end
    end

    private

    def with_voice_env(overrides = {})
      keys = %w[
        TTS_PROVIDER TTS_VOICE_EN TTS_VOICE_HOST TTS_VOICE_COHOST
        KOKORO_VOICE_HOST KOKORO_VOICE_COHOST
      ]
      previous = keys.index_with { |key| ENV[key] }
      keys.each { |key| ENV.delete(key) }
      ENV["TTS_PROVIDER"] = "openai"
      overrides.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each do |key, value|
        value ? ENV[key] = value : ENV.delete(key)
      end
    end
  end
end
