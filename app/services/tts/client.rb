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
    STYLE_VERSION = "radio-v2"
    # Cedar and marin are OpenAI's recommended highest-quality built-in
    # voices. Cedar's grounded delivery is a better default for a station
    # presenter than the neutral, assistant-like alloy voice.
    DEFAULT_VOICE = "cedar"

    DELIVERY = {
      "nl" => {
        base: <<~PROMPT.squish,
          Spreek natuurlijk Nederlands met een Nederlands accent, als een ervaren
          presentator in een professionele radiostudio. Gebruik een warme,
          zelfverzekerde close-mic stem, natuurlijke adempauzes en subtiele nadruk.
          Spreek tegen één luisteraar. Klink nooit als een AI-assistent, luisterboek,
          reclame, voice-over of overdreven omroeper. Verander de tekst niet.
          Spreek artiesten en titels natuurlijk uit, zo nodig in hun oorspronkelijke taal.
        PROMPT
        intro: <<~PROMPT.squish,
          Breng dit als een ontspannen muziekradio-link: licht energiek, spontaan en
          met een glimlach in de stem. Laat de overgang vloeien alsof je live uit een
          plaat komt, zonder gemaakte opwinding.
        PROMPT
        news: <<~PROMPT.squish,
          Breng dit als een bondig radiojournaal: rustig gezaghebbend, neutraal en
          helder, met een korte natuurlijke pauze tussen onderwerpen. Geen dramatiek.
        PROMPT
        weather: <<~PROMPT.squish
          Breng dit als een korte live tijd- en weercheck tussen twee platen:
          ontspannen, nuttig en terloops.
        PROMPT
      },
      "en" => {
        base: <<~PROMPT.squish,
          Speak in natural broadcast English like an experienced presenter in a
          professional radio studio. Use a warm, confident close-mic voice, natural
          breaths, varied phrasing, and subtle emphasis. Speak to one listener.
          Never sound like an AI assistant, audiobook, advert, voice-over, or
          exaggerated announcer. Do not change the words. Pronounce artists and
          titles naturally, in their original language when appropriate.
        PROMPT
        intro: <<~PROMPT.squish,
          Deliver this as a relaxed contemporary music-radio link: lightly upbeat,
          spontaneous, and smiling. Flow naturally out of the previous record and
          into the next one, without fake excitement.
        PROMPT
        news: <<~PROMPT.squish,
          Deliver this as a concise radio news bulletin: composed, neutral,
          authoritative, and crisp, with a short natural pause between stories.
          Avoid melodrama.
        PROMPT
        weather: <<~PROMPT.squish
          Deliver this as a quick live time-and-weather check between records:
          relaxed, useful, and conversational.
        PROMPT
      }
    }.freeze

    class << self
      def synthesize(text:, language:, kind:)
        provider.synthesize(
          text: text,
          voice: voice_for(language),
          instructions: instructions_for(language, kind)
        )
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

      def instructions_for(language, kind)
        delivery = DELIVERY.fetch(language, DELIVERY.fetch("en"))
        [ delivery.fetch(:base), delivery.fetch(kind.to_sym, "") ].reject(&:blank?).join(" ")
      end
    end
  end
end
