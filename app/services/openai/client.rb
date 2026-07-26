require "net/http"

module Openai
  # Thin wrapper around the OpenAI API: writes the talk scripts (chat
  # completions) and voices them (audio/speech). Plain Net::HTTP, matching the
  # other API clients.
  class Client
    BASE_URL = "https://api.openai.com/v1"
    OPEN_TIMEOUT_SECONDS = 10
    TEXT_TIMEOUT_SECONDS = 60
    SPEECH_TIMEOUT_SECONDS = 60
    TTS_MODEL = "gpt-4o-mini-tts"

    class Error < StandardError; end

    class << self
      # -> String (the completion text)
      def complete(system:, user:, max_tokens: 700)
        json = post_json("/chat/completions", {
          model: ENV.fetch("OPENAI_TEXT_MODEL", "gpt-4o-mini"),
          max_completion_tokens: max_tokens,
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        }, timeout: TEXT_TIMEOUT_SECONDS)

        text = json.dig("choices", 0, "message", "content").to_s.strip
        raise Error, "empty completion" if text.empty?

        text
      end

      # -> String (raw MP3 bytes)
      def speech(text:, voice:)
        response = post("/audio/speech", {
          model: TTS_MODEL,
          voice: voice,
          input: text,
          response_format: "mp3"
        }, timeout: SPEECH_TIMEOUT_SECONDS)
        raise Error, "speech request failed (#{response.code})" unless response.is_a?(Net::HTTPOK)

        response.body
      end

      private

      def post_json(path, body, timeout:)
        response = post(path, body, timeout: timeout)
        raise Error, "request failed (#{response.code})" unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)
      end

      def post(path, body, timeout:)
        uri = URI("#{BASE_URL}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
          open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: timeout) do |http|
          http.request(request)
        end
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "request failed: #{e.message}"
      end
    end
  end
end
