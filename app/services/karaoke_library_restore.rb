# One-off repair after the all-in-one app rekeyed the shared songs table by
# YouTube video id (its KeySongsByYoutubeId migration plus a YoutubeRemap
# run, 2026-09-21). That remap rewrote every songs row and moved the scores
# and plays with it, but knew nothing about this app's files: the cached
# MP3s and karaoke artifacts under storage/audio stayed keyed by ISRC, and
# the mapping it chose was printed to a terminal and kept nowhere.
#
# So a prepared karaoke song now has its artifacts but no Song row (scoring
# it fails on the foreign key, and the library list hides it), while its old
# scores sit under a YouTube id this app never prepared. This puts both
# back:
#
#   * every ISRC with a cached file and no row gets its row again, from the
#     same Deezer lookup SongCache uses when it first downloads a track;
#   * the remap copied title and artist verbatim onto the new row, so when
#     exactly one YouTube-keyed row carries this track's title and artist,
#     the scores under it are moved back to the ISRC the artifacts and the
#     search results use. The YouTube row itself is left alone — it is the
#     other app's.
#
# Idempotent: rows that exist are skipped, and scores are only ever moved
# off a YouTube id. Run with `bin/rails karaoke:restore_song_rows`.
class KaraokeLibraryRestore
  # Deezer allows roughly fifty requests per five seconds.
  PAUSE_SECONDS = 0.15

  Result = Struct.new(:restored, :scores_moved, :missing, keyword_init: true)

  def initialize(logger: method(:puts))
    @log = logger
  end

  # Prepared (separated) songs first: those are the ones a party would pick
  # tonight, and the ones whose missing row breaks scoring.
  def run(only_prepared: false)
    result = Result.new(restored: 0, scores_moved: 0, missing: [])
    isrcs = only_prepared ? prepared : prepared + (cached - prepared)
    isrcs -= Song.where(id: isrcs).pluck(:id)
    @log.call("#{isrcs.size} cached tracks without a Song row")

    isrcs.each do |isrc|
      details = track_details(isrc)
      if details.nil?
        result.missing << isrc
        next
      end

      SongCache.create_song(isrc, details)
      result.restored += 1
      moved = reunite_scores(isrc, details)
      result.scores_moved += moved
      @log.call("#{isrc}  #{details.dig("artist", "name")} - #{details["title"]}#{"  (#{moved} scores moved back)" if moved.positive?}")
      sleep PAUSE_SECONDS
    end

    @log.call("Restored #{result.restored} rows, moved #{result.scores_moved} scores; Deezer knows nothing of #{result.missing.size}: #{result.missing.join(", ")}")
    result
  end

  private

  def prepared
    VocalSeparation.prepared_isrcs.reject { |isrc| YoutubeTrack.isrc?(isrc) }
  end

  def cached
    Dir.glob(SongCache::AUDIO_DIR.join("*.mp3"))
      .map { |path| File.basename(path, ".mp3") }
      .reject { |name| name.end_with?(".instrumental", ".vocals") || YoutubeTrack.isrc?(name) || name.start_with?("talk-") }
      .sort
  end

  # nil for an ISRC Deezer no longer resolves: it answers 200 with an error
  # body rather than a non-OK status (see SpotifyController#lyrics_lookup_attrs).
  def track_details(isrc)
    details = Deezer::Client.track_details(isrc)
    details if details["title"].present?
  rescue Deezer::Client::Error, JSON::ParserError, SocketError, Timeout::Error, Errno::ECONNRESET => e
    @log.call("#{isrc}  Deezer lookup failed: #{e.class}: #{e.message}")
    nil
  end

  # Only on an unambiguous match: two YouTube rows with the same title and
  # artist means two editions were collapsed differently, and guessing would
  # hand one song's scores to another.
  def reunite_scores(isrc, details)
    twins = Song.where(title: details["title"], artist: details.dig("artist", "name"))
                .where.not(id: isrc)
                .pluck(:id)
                .select { |id| id.match?(YoutubeTrack::BARE_ID_FORMAT) }
    return 0 unless twins.size == 1

    KaraokeScore.where(song_id: twins.first).update_all(song_id: isrc)
  end
end
