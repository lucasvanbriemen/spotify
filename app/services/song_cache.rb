# Downloads and caches song MP3s under storage/audio, one file per ISRC.
# Used synchronously by the get-mp3 endpoint and asynchronously by
# CacheSongJob to warm songs before they are requested.
#
# The download itself runs through a ComputeSession, so it happens on the GPU
# box when that box is up. The reason is not its GPU — a download is not
# CPU-bound — but its address: the whole YtDlp player-client walk exists
# because YouTube serves this datacenter IP a blanket 403, and a home
# connection is not treated that way. The file still lands here, in
# storage/audio, because this is what serves it.
class SongCache
  AUDIO_DIR = Rails.root.join("storage/audio")
  DOWNLOAD_TIMEOUT_SECONDS = 180
  # What the download is called inside a session's scratch directory. Fixed,
  # so an ISRC — or the pseudo-ISRC of a pasted link — never has to be a
  # filename on another host.
  DOWNLOAD_NAME = "download.mp3".freeze
  # YouTube carries single edits, radio edits, live takes and remasters under
  # the same title, and picking the wrong one puts the audio out of step with
  # everything timed against the real recording — most visibly the karaoke
  # lyrics, which come from LRCLIB timed to the released master. (Observed: a
  # 271s song whose search result was a 241s edit, drifting half a minute by
  # the end.) Prefer a result whose length matches what Deezer reports.
  DURATION_TOLERANCE = 0.07

  class << self
    def path(isrc)
      AUDIO_DIR.join("#{isrc}.mp3")
    end

    def cached?(isrc)
      path(isrc).file?
    end

    # Makes sure the MP3 for the ISRC is on disk and its Song row exists.
    # Concurrency-safe: a per-ISRC file lock makes simultaneous callers (a
    # prewarm job and a listener clicking the song) wait on one download
    # instead of spawning duplicate yt-dlp processes.
    def ensure_cached(isrc)
      return true if cached?(isrc)

      with_lock(isrc) do
        next true if cached?(isrc) # downloaded while we waited for the lock
        next cache_youtube(isrc) if YoutubeTrack.isrc?(isrc)

        details = Deezer::Client.track_details(isrc)
        download(isrc, details)
        # Nothing on YouTube matched the expected length. Better a
        # possibly-mismatched recording than no song at all.
        download(isrc, details, match_duration: false) unless cached?(isrc)
        next false unless cached?(isrc)

        create_song(isrc, details)
        true
      end
    end

    private

    # A pasted YouTube link names the upload outright, so there is no search
    # to run and no duration window to satisfy — the singer already chose
    # which one they meant. The Song row is written from the video's own
    # metadata; Deezer has never heard of this ISRC.
    def cache_youtube(isrc)
      details = YoutubeTrack.track_details(isrc)
      return false unless details

      downloaded = ComputeSession.open("download #{isrc}") do |session|
        YoutubeTrack.download(session: session, isrc: isrc, name: DOWNLOAD_NAME) &&
          session.fetch(DOWNLOAD_NAME, path(isrc))
      end
      return false unless downloaded

      create_song(isrc, details)
      true
    end

    def with_lock(isrc)
      FileUtils.mkdir_p(AUDIO_DIR)
      File.open(AUDIO_DIR.join("#{isrc}.lock"), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def create_song(isrc, details)
      return if Song.exists?(isrc: isrc)

      Song.create!(
        isrc: isrc,
        title: details["title"],
        artist: details.dig("artist", "name"),
        image_url: details.dig("album", "cover_medium") || Song::PLACEHOLDER_IMAGE,
        album: details.dig("album", "title"),
        duration: details["duration"],
        genre: SongEnrichment.genre_for(details.dig("album", "id")),
        enriched_at: Time.current,
        **SongEnrichment.attributes_from_track(details)
      )
    end

    def download(isrc, details, match_duration: true)
      ComputeSession.open("download #{isrc}") do |session|
        options = [
          session.tool("yt-dlp"),
          # Without a JavaScript runtime YouTube withholds every audio format
          # and the search returns nothing downloadable — see YtDlp.
          *YtDlp.media_options,
          "--no-playlist",
          # Audio-only formats and parallel fragment downloads: never pull the
          # video track, and sidestep YouTube's per-connection throttling.
          "--format", "bestaudio/best",
          "--concurrent-fragments", "4",
          "--extract-audio",
          "--audio-format", "mp3",
          "--audio-quality", "0",
          "--restrict-filenames",
          "--no-progress",
          # yt-dlp walks the search results in order and --max-downloads stops at
          # the first that passes, so the length window here is what keeps a
          # different edit from being taken.
          "--match-filter", match_filter(match_duration ? details["duration"] : nil),
          "--max-downloads", "1",
          "--ffmpeg-location", session.bin_dir,
          # The extension is yt-dlp's to add, so the template goes without it.
          "--output", session.path(DOWNLOAD_NAME.delete_suffix(".mp3"))
        ]
        search = "ytsearch5: #{details.dig("artist", "name")} #{details["title"]} audio"

        # Once per player client, stopping at the first that actually produces the
        # file — a client YouTube is 403ing fails every candidate in the search,
        # so without this a downloadable song still reads as unavailable.
        #
        # The exit status is ignored, like in the Laravel app: callers respond
        # with 404 when no file was produced, and that is also what decides here
        # whether the next client is worth trying. yt-dlp in particular exits
        # non-zero when --max-downloads stops it, having produced exactly the
        # file that was asked for.
        YtDlp.download_attempts.each do |client_options|
          result = session.run(
            *options, *client_options, search,
            outputs: [ DOWNLOAD_NAME ], timeout_seconds: DOWNLOAD_TIMEOUT_SECONDS
          )
          break if result.produced?(DOWNLOAD_NAME) && session.fetch(DOWNLOAD_NAME, path(isrc))
        end
      end
    end

    def match_filter(expected_duration)
      seconds = expected_duration.to_f
      return "age_limit<18" unless seconds.positive?

      window = seconds * DURATION_TOLERANCE
      "age_limit<18 & duration>#{(seconds - window).round} & duration<#{(seconds + window).round}"
    end
  end
end
