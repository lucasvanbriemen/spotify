module Tts
  class Error < StandardError; end

  # Provider-agnostic text-to-speech: returns raw MP3 bytes. The provider is
  # picked via TTS_PROVIDER so a future voice-provider upgrade is a config
  # change, not a pipeline change. A short-lived circuit
  # breaker stops the queue builder from minting new talk segments while the
  # provider is down.
  class Client
    BREAKER_KEY = "talk/tts_down"
    BREAKER_TTL = 10.minutes
    STYLE_VERSION = "radio-v5"
    # OpenAI recommends marin and cedar for its highest-quality built-in
    # speech. Give them stable on-air roles so occasional conversations sound
    # like two people rather than one voice changing character.
    DEFAULT_HOST_VOICE = "marin"
    DEFAULT_COHOST_VOICE = "cedar"

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
          Speak in natural conversational English, as if you are talking to one
          listener without reading from a script. Use contractions, small changes
          of pace, relaxed sentence endings, and brief natural breaths. Keep the
          delivery understated and slightly imperfect. Avoid a polished commercial
          voice-over cadence, symmetrical emphasis, forced warmth, or announcer
          projection. Do not change the words. Pronounce artists and titles
          naturally, in their original language when appropriate.
        PROMPT
        intro: <<~PROMPT.squish,
          This is an off-the-cuff link between songs on a contemporary music
          station. Sound present and casually engaged. Let short phrases stay
          short; do not turn every sentence into a performance.
        PROMPT
        news: <<~PROMPT.squish,
          Read this concise bulletin calmly and clearly. Keep it neutral and
          grounded, with a real pause between stories. Avoid newsreader grandeur,
          melodrama, or artificial urgency.
        PROMPT
        weather: <<~PROMPT.squish
          Treat this as a quick time-and-weather aside between records: useful,
          unpolished, and conversational.
        PROMPT
      }
    }.freeze

    SPEAKER_DELIVERY = {
      "host" => "You are the main host. Keep an easy, dry confidence and never oversell the link.",
      "cohost" => "You are the second host. Sound distinct, relaxed, responsive, and a little more understated."
    }.freeze

    ELEVENLABS_DELIVERY = {
      "intro" => {
        "host" => "casual, conversational, speaking off the cuff",
        "cohost" => "responding naturally, relaxed and understated"
      },
      "news" => {
        "host" => "calm, direct and matter-of-fact",
        "cohost" => "calm and attentive"
      },
      "weather" => {
        "host" => "a casual aside, relaxed and useful",
        "cohost" => "responding naturally and briefly"
      }
    }.freeze

    class << self
      def synthesize_lines(lines:, language:, kind:)
        if lines.many? && provider.respond_to?(:synthesize_dialogue)
          [
            provider.synthesize_dialogue(
              lines: lines,
              voices: lines.map { |line| voice_for(language, line.fetch(:speaker)) },
              instructions: lines.map { |line| provider_instructions(kind, line.fetch(:speaker)) }
            )
          ]
        else
          lines.map do |line|
            synthesize(
              text: line.fetch(:text),
              language: language,
              kind: kind,
              speaker: line.fetch(:speaker)
            )
          end
        end
      rescue Error
        raise
      rescue StandardError => e
        Rails.cache.write(BREAKER_KEY, true, expires_in: BREAKER_TTL)
        raise Error, e.message
      end

      def synthesize(text:, language:, kind:, speaker: "host")
        provider.synthesize(
          text: text,
          voice: voice_for(language, speaker),
          instructions: provider_instructions(kind, speaker, language: language)
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
        when "elevenlabs" then Providers::Elevenlabs
        when "kokoro" then Providers::Kokoro
        else raise Error, "unknown TTS provider #{ENV['TTS_PROVIDER'].inspect}"
        end
      end

      def voice_for(language, speaker)
        if ENV.fetch("TTS_PROVIDER", "openai") == "elevenlabs"
          return ENV.fetch(speaker == "cohost" ? "ELEVENLABS_VOICE_COHOST_ID" : "ELEVENLABS_VOICE_HOST_ID")
        end
        if ENV.fetch("TTS_PROVIDER", "openai") == "kokoro"
          return ENV.fetch(speaker == "cohost" ? "KOKORO_VOICE_COHOST" : "KOKORO_VOICE_HOST")
        end

        return ENV.fetch("TTS_VOICE_NL", DEFAULT_HOST_VOICE) if language == "nl"

        if speaker == "cohost"
          ENV.fetch("TTS_VOICE_COHOST", DEFAULT_COHOST_VOICE)
        else
          ENV.fetch("TTS_VOICE_HOST", ENV.fetch("TTS_VOICE_EN", DEFAULT_HOST_VOICE))
        end
      end

      def instructions_for(language, kind, speaker)
        delivery = DELIVERY.fetch(language, DELIVERY.fetch("en"))
        [
          delivery.fetch(:base),
          delivery.fetch(kind.to_sym, ""),
          SPEAKER_DELIVERY.fetch(speaker, SPEAKER_DELIVERY.fetch("host"))
        ].reject(&:blank?).join(" ")
      end

      def provider_instructions(kind, speaker, language: "en")
        if ENV.fetch("TTS_PROVIDER", "openai") == "elevenlabs"
          delivery = ELEVENLABS_DELIVERY.fetch(kind.to_s, ELEVENLABS_DELIVERY.fetch("intro"))
          delivery.fetch(speaker, delivery.fetch("host"))
        else
          instructions_for(language, kind, speaker)
        end
      end
    end
  end
end
