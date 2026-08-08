require "net/http"

module Lrclib
  # Thin wrapper around the LRCLIB lyrics API (previously inlined in
  # SpotifyController#lyrics). Shared with KaraokeSearch, which needs to
  # know whether a track has synced lyrics *before* it's shown as a result.
  class Client
    GET_URL = "https://lrclib.net/api/get"
    CACHE_TTL = 7.days
    TIMEOUT_SECONDS = 5

    class << self
      # { "plainLyrics" => ..., "syncedLyrics" => ... } (LRCLIB's own key
      # casing, passed straight through), or {} on a miss. Cached per
      # artist/title/duration since karaoke search checks this for every
      # result on every keystroke — but only a confirmed miss (LRCLIB 404)
      # is cached; a timeout or other transient failure is not, or a single
      # LRCLIB outage would poison every song's lyrics for a week (skip_nil).
      def fetch(artist:, title:, album:, duration:)
        key = "lrclib/v1/#{artist.to_s.downcase}/#{title.to_s.downcase}/#{duration}"
        Rails.cache.fetch(key, expires_in: CACHE_TTL, skip_nil: true) { request(artist:, title:, album:, duration:) } || {}
      end

      private

      def request(artist:, title:, album:, duration:)
        uri = URI(GET_URL)
        # "durration" [sic] mirrors the query the Laravel app sent.
        uri.query = URI.encode_www_form(
          artist_name: artist, track_name: title, album_name: album, durration: duration
        )

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        return {} if response.is_a?(Net::HTTPNotFound)
        return nil unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)
      rescue StandardError
        nil
      end
    end
  end
end
