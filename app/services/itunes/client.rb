require "net/http"

module Itunes
  # Thin wrapper around the Apple iTunes Search API. Used as the primary
  # song search because its relevance is far better than Deezer's: it is
  # typo tolerant and matches lyric fragments, and it needs no API key.
  # Failures degrade to an empty list, like Deezer searches.
  class Client
    BASE_URL = "https://itunes.apple.com/search"
    # Shorter than Deezer's timeout: when iTunes throttles (~20 req/min per
    # IP) the search degrades to Deezer's own ranking, and waiting longer
    # only stalls that fallback.
    TIMEOUT_SECONDS = 3
    COUNTRY = "NL"

    class << self
      def search_tracks(query, limit: 15)
        uri = URI(BASE_URL)
        uri.query = URI.encode_www_form(term: query, entity: "song", country: COUNTRY, limit: limit)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        return [] unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)["results"] || []
      rescue StandardError
        []
      end
    end
  end
end
