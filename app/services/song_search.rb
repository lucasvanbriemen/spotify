# Hybrid song search. Apple's iTunes Search API has far better relevance
# than Deezer (typo tolerant, lyric fragments find the original song instead
# of karaoke covers), but the rest of the app is keyed on ISRCs, which
# iTunes doesn't expose. So: search iTunes for the ranking, then resolve
# each hit to a Deezer track (ISRC + the metadata shape the app already
# uses). Most hits resolve for free against the Deezer results fetched for
# the same query; the rest (typically lyric searches, where Deezer misses
# the song entirely) fall back to cached, concurrent Deezer lookups.
# Deezer's own ranking remains the fallback when iTunes finds nothing, and
# playlist search stays on Deezer.
class SongSearch
  RESULT_CACHE_TTL = 10.minutes
  RESOLVE_CACHE_TTL = 30.days
  TRACK_LIMIT = 15
  # Each network resolution is an extra Deezer round trip (~0.5s, all in
  # parallel); unmatched hits past this budget are tail results and get
  # dropped rather than slowing every search down.
  MAX_NETWORK_RESOLUTIONS = 5

  class << self
    def search(query)
      Rails.cache.fetch("song_search/v1/#{query.downcase}", expires_in: RESULT_CACHE_TTL) do
        perform(query)
      end
    end

    private

    def perform(query)
      itunes = Concurrent::Promises.future { Itunes::Client.search_tracks(query, limit: TRACK_LIMIT) }
      deezer = Concurrent::Promises.future { Deezer::Client.search(query) }

      deezer_results = deezer.value!
      tracks = resolve_tracks(itunes.value!, deezer_results[:tracks])
      tracks = deezer_results[:tracks] if tracks.empty?

      { tracks: tracks, playlists: deezer_results[:playlists] }
    end

    # Resolves iTunes hits to Deezer tracks, keeping iTunes' ranking and
    # dropping hits Deezer doesn't know.
    def resolve_tracks(itunes_tracks, deezer_tracks)
      local_index = index_by_artist_title(deezer_tracks)
      budget = MAX_NETWORK_RESOLUTIONS

      futures = itunes_tracks.map do |track|
        artist, title = track["artistName"], track["trackName"]
        local = local_index[match_key(artist, title)] || local_index[match_key(artist, bare_title(title))]

        if local
          Concurrent::Promises.fulfilled_future(local)
        elsif budget.positive?
          budget -= 1
          Concurrent::Promises.future { resolve_track(artist, title) }
        else
          Concurrent::Promises.fulfilled_future(nil)
        end
      end

      futures.map(&:value!).compact.uniq { |track| track["isrc"] }
    end

    # Indexes the Deezer search results under both the exact and the bare
    # (no "(Remaster)" etc. suffix) artist/title keys.
    def index_by_artist_title(deezer_tracks)
      deezer_tracks.each_with_object({}) do |track, index|
        next if track["isrc"].blank?

        artist = track.dig("artist", "name")
        index[match_key(artist, track["title"])] ||= track
        index[match_key(artist, bare_title(track["title"]))] ||= track
      end
    end

    def resolve_track(artist, title)
      return nil if artist.blank? || title.blank?

      Rails.cache.fetch("deezer_track/v1/#{artist.downcase}/#{title.downcase}", expires_in: RESOLVE_CACHE_TTL) do
        candidates = Deezer::Client.search_tracks("#{artist} #{title}", limit: 5)
        # iTunes suffixes like "(2024 Remaster)" can miss on Deezer; retry bare.
        candidates = Deezer::Client.search_tracks("#{artist} #{bare_title(title)}", limit: 5) if candidates.empty? && bare_title(title) != title

        best_match(candidates, artist)
      end
    end

    # Prefer a candidate by the same artist so covers of popular songs don't
    # hijack the resolution; Deezer's own first result is the last resort.
    def best_match(candidates, artist)
      candidates = candidates.select { |track| track["isrc"].present? }
      candidates.find { |track| same_artist?(track.dig("artist", "name"), artist) } || candidates.first
    end

    def match_key(artist, title)
      "#{normalize(artist)}/#{normalize(title)}"
    end

    def bare_title(title)
      title.to_s.gsub(/\s*[\(\[].*?[\)\]]/, "").strip
    end

    def same_artist?(a, b)
      a, b = normalize(a), normalize(b)
      a == b || a.include?(b) || b.include?(a)
    end

    def normalize(name)
      name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
