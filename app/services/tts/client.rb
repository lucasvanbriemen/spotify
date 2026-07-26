module Tts
  class Error < StandardError; end

  # Provider-agnostic text-to-speech: returns raw MP3 bytes. The provider is
  # picked via TTS_PROVIDER so a voice upgrade (e.g. ElevenLabs for better
  # Dutch) is a config change, not a pipeline change. A short-lived circuit
  # breaker stops the queue builder from minting new talk segments while the
  # provider is down.
  class Client
    BREAKER_KEY = "talk/tts_down"
    BREAKER_TTL = 10.minutes
    DEFAULT_VOICE = "alloy"

    class << self
      def synthesize(text:, language:)
        provider.synthesize(text: text, voice: voice_for(language))
      rescue Error
        raise
      rescue StandardError => e
        Rails.cache.write(BREAKER_KEY, true, expires_in: BREAKER_TTL)
        raise Error, e.message
      end

      def down?
        Rails.cache.read(BREAKER_KEY).present?
      end

      private

      def provider
        case ENV.fetch("TTS_PROVIDER", "openai")
        when "openai" then Providers::Openai
        else raise Error, "unknown TTS provider #{ENV['TTS_PROVIDER'].inspect}"
        end
      end

      def voice_for(language)
        ENV.fetch(language == "nl" ? "TTS_VOICE_NL" : "TTS_VOICE_EN", DEFAULT_VOICE)
      end
    end
  end
end
