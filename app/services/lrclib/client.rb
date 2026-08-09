require "net/http"

module Lrclib
  # Thin wrapper around the LRCLIB lyrics API (previously inlined in
  # SpotifyController#lyrics). Shared with KaraokeSearch, which needs to
  # know whether a track has synced lyrics *before* it's shown as a result.
  class Client
    GET_URL = "https://lrclib.net/api/get"
    CACHE_TTL = 7.days
    TIMEOUT_SECONDS = 5
    # Lyrics timed to a different edit are worse than no lyrics: karaoke plays
    # them against our audio, so any length difference is heard as the words
    # drifting. LRCLIB matches on duration itself, but its answer is checked
    # here too in case a near-miss slips through.
    DURATION_TOLERANCE_SECONDS = 5

    class << self
      # { "plainLyrics" => ..., "syncedLyrics" => ... } (LRCLIB's own key
      # casing, passed straight through), or {} on a miss. Cached per
      # artist/title/duration since karaoke search checks this for every
      # result on every keystroke — but only a confirmed miss (LRCLIB 404)
      # is cached; a timeout or other transient failure is not, or a single
      # LRCLIB outage would poison every song's lyrics for a week (skip_nil).
      def fetch(artist:, title:, album:, duration:)
        # v2: v1 entries were fetched with the duration filter silently
        # disabled (see #request) and can hold another edit's lyrics.
        key = "lrclib/v2/#{artist.to_s.downcase}/#{title.to_s.downcase}/#{duration}"
        Rails.cache.fetch(key, expires_in: CACHE_TTL, skip_nil: true) { request(artist:, title:, album:, duration:) } || {}
      end

      private

      def request(artist:, title:, album:, duration:)
        uri = URI(GET_URL)
        # The Laravel app spelled this "durration", and the typo was carried
        # over faithfully — which meant LRCLIB ignored it and answered with
        # whichever edit it liked. For "Video Killed The Radio Star" that was a
        # 254s version against our 201s recording, so the words drifted further
        # out of step the longer the song ran.
        uri.query = URI.encode_www_form(
          artist_name: artist, track_name: title, album_name: album, duration: duration
        )

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        return {} if response.is_a?(Net::HTTPNotFound)
        return nil unless response.is_a?(Net::HTTPOK)

        body = JSON.parse(response.body)
        matching_duration?(body["duration"], duration) ? body : {}
      rescue StandardError
        nil
      end

      # An unknown length on either side isn't evidence of a mismatch, so it
      # passes; only a measured difference rejects.
      def matching_duration?(found, expected)
        return true if found.to_f.zero? || expected.to_f.zero?

        (found.to_f - expected.to_f).abs <= DURATION_TOLERANCE_SECONDS
      end
    end
  end
end
