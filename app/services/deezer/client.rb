require "net/http"

module Deezer
  # Thin wrapper around the Deezer public API (port of the Laravel
  # DeezerHelper). Search failures degrade to empty lists; detail lookups
  # raise so callers surface the failure.
  class Client
    BASE_URL = "https://api.deezer.com"
    TIMEOUT_SECONDS = 5

    class Error < StandardError; end

    class << self
      # Searches tracks and playlists concurrently (the Laravel app used
      # Http::pool for the same effect).
      def search(query)
        tracks = Concurrent::Promises.future { data_from(get("/search/track", q: query, limit: 100)) }
        playlists = Concurrent::Promises.future { data_from(get("/search/playlist", q: query, limit: 25)) }

        { tracks: tracks.value!, playlists: playlists.value! }
      end

      def track_details(isrc)
        request("/track/isrc:#{isrc}")
      end

      def playlist_details(id)
        request("/playlist/#{id}")
      end

      private

      def request(path, params = {})
        response = get(path, params)
        raise Error, "Failed to fetch data from Deezer API" unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)
      end

      def data_from(response)
        return [] unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)["data"] || []
      end

      # Returns the Net::HTTPResponse, or nil when the request failed or
      # timed out.
      def get(path, params = {})
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params) if params.any?

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
      rescue StandardError
        nil
      end
    end
  end
end
