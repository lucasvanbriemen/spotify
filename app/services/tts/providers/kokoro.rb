require "net/http"

module Tts
  module Providers
    # Free, self-hosted Kokoro-82M speech. The model stays warm in a
    # localhost-only Python service managed by Supervisor.
    class Kokoro
      ENDPOINT = "http://127.0.0.1:8765/synthesize"
      TIMEOUT_SECONDS = 120

      class Error < StandardError; end

      class << self
        def synthesize(text:, voice:, instructions:)
          uri = URI(ENV.fetch("KOKORO_URL", ENDPOINT))
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(
            text: text,
            voice: voice,
            speed: ENV.fetch("KOKORO_SPEED", "1.0").to_f
          )

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            open_timeout: 5,
            read_timeout: TIMEOUT_SECONDS
          ) { |http| http.request(request) }
          return response.body if response.is_a?(Net::HTTPOK)

          raise Error, "Kokoro speech request failed (#{response.code})"
        rescue Error
          raise
        rescue StandardError => e
          raise Error, "Kokoro speech request failed: #{e.message}"
        end
      end
    end
  end
end
