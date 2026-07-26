require "net/http"

module Tts
  module Providers
    # ElevenLabs v3 speech and dialogue. Dialogue is generated in one request
    # so turns share timing and conversational context instead of sounding like
    # unrelated voice-over clips joined together.
    class Elevenlabs
      BASE_URL = "https://api.elevenlabs.io"
      MODEL = "eleven_v3"
      TIMEOUT_SECONDS = 90

      class Error < StandardError; end

      class << self
        def synthesize(text:, voice:, instructions:)
          post(
            "/v1/text-to-speech/#{voice}?output_format=mp3_44100_128",
            {
              text: directed_text(text, instructions),
              model_id: ENV.fetch("ELEVENLABS_MODEL", MODEL),
              language_code: "en",
              apply_text_normalization: "auto"
            }
          )
        end

        def synthesize_dialogue(lines:, voices:, instructions:)
          inputs = lines.zip(voices, instructions).map do |line, voice, direction|
            {
              text: directed_text(line.fetch(:text), direction),
              voice_id: voice
            }
          end

          post(
            "/v1/text-to-dialogue?output_format=mp3_44100_128",
            {
              inputs: inputs,
              model_id: ENV.fetch("ELEVENLABS_MODEL", MODEL),
              language_code: "en",
              apply_text_normalization: "auto"
            }
          )
        end

        private

        def directed_text(text, instructions)
          "[#{instructions}] #{text}"
        end

        def post(path, body)
          uri = URI("#{BASE_URL}#{path}")
          request = Net::HTTP::Post.new(uri)
          request["xi-api-key"] = ENV.fetch("ELEVENLABS_API_KEY")
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true,
            open_timeout: 10,
            read_timeout: TIMEOUT_SECONDS
          ) { |http| http.request(request) }
          return response.body if response.is_a?(Net::HTTPOK)

          raise Error, "ElevenLabs speech request failed (#{response.code})"
        rescue Error
          raise
        rescue StandardError => e
          raise Error, "ElevenLabs speech request failed: #{e.message}"
        end
      end
    end
  end
end
