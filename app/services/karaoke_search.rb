# Like SongSearch, but filtered down to tracks LRCLIB confirms have synced
# (line-timed) lyrics — the only kind the karaoke view can highlight against
# playback. Checks run concurrently against SongSearch's own result set, so
# a karaoke search costs at most one extra round trip on top of a normal one.
class KaraokeSearch
  RESULT_CACHE_TTL = 10.minutes
  # Checking lyrics for every hit would fan out to dozens of LRCLIB requests
  # per keystroke; cap it to the tracks a user would actually scroll to.
  MAX_LYRICS_CHECKS = 15

  class << self
    def search(query)
      # skip_nil + presence: an empty result isn't cached. Cheap to recompute,
      # and caching it would let a transient LRCLIB outage look like "no
      # karaoke-ready songs" for the full TTL instead of just that one search.
      Rails.cache.fetch("karaoke_search/v1/#{query.downcase}", expires_in: RESULT_CACHE_TTL, skip_nil: true) do
        perform(query).presence
      end || []
    end

    private

    def perform(query)
      tracks = SongSearch.search(query)[:tracks].first(MAX_LYRICS_CHECKS)
      synced = tracks.map { |track| Concurrent::Promises.future { synced_lyrics?(track) } }.map(&:value!)

      tracks.zip(synced).select { |_track, has_synced_lyrics| has_synced_lyrics }.map(&:first)
    end

    def synced_lyrics?(track)
      Lrclib::Client.fetch(
        artist: track.dig("artist", "name"),
        title: track["title"],
        album: track.dig("album", "title"),
        duration: track["duration"]
      )["syncedLyrics"].present?
    end
  end
end
