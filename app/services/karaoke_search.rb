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
      # A pasted YouTube link is a request for that video, not a search to
      # filter: it is shown whether or not LRCLIB knows the song. Without
      # synced lyrics the stage has no words to sweep, but the pitch lane and
      # the scoring still work — those come from the vocal stem, not the
      # lyrics — so the song is singable either way.
      return SongSearch.search(query)[:tracks] if YoutubeTrack.url?(query)

      # skip_nil + presence: an empty result isn't cached. Cheap to recompute,
      # and caching it would let a transient LRCLIB outage look like "no
      # karaoke-ready songs" for the full TTL instead of just that one search.
      Rails.cache.fetch("karaoke_search/v1/#{query.downcase}", expires_in: RESULT_CACHE_TTL, skip_nil: true) do
        perform(query).presence
      end || []
    end

    # The same hits, shaped the way a karaoke result row draws them. Used by
    # the remote's search, which has no business handing a phone the playlist
    # membership map SpotifyController#search returns.
    #
    # Readiness is annotated out here rather than inside the cached search: a
    # song that just finished separating should get its badge on the next
    # keystroke, not when the TTL expires.
    def results(query)
      search(query).select { |track| track["isrc"].present? }.map do |track|
        {
          isrc: track["isrc"],
          title: track["title"],
          artist: track.dig("artist", "name"),
          image_url: track.dig("album", "cover_medium") || Song::PLACEHOLDER_IMAGE,
          duration: track["duration"],
          ready: VocalSeparation.ready?(track["isrc"]),
          difficulty: VocalSeparation.difficulty(track["isrc"])&.dig("level")
        }
      end
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
