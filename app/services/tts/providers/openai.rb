module Tts
  module Providers
    # OpenAI TTS: one POST, MP3 bytes back.
    class Openai
      def self.synthesize(text:, voice:)
        ::Openai::Client.speech(text: text, voice: voice)
      end
    end
  end
end
