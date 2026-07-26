module Tts
  module Providers
    # OpenAI TTS: one POST, MP3 bytes back.
    class Openai
      def self.synthesize(text:, voice:, instructions:)
        ::Openai::Client.speech(text: text, voice: voice, instructions: instructions)
      end
    end
  end
end
