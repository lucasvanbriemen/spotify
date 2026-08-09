# Downloads and caches song MP3s under storage/audio, one file per ISRC.
# Used synchronously by the get-mp3 endpoint and asynchronously by
# CacheSongJob to warm songs before they are requested.
class SongCache
  AUDIO_DIR = Rails.root.join("storage/audio")
  DOWNLOAD_TIMEOUT_SECONDS = 180
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
      tmp_dir = Rails.root.join("tmp/yt-dlp")
      FileUtils.mkdir_p(tmp_dir)
      FileUtils.mkdir_p(AUDIO_DIR)

      env = { "TMP" => tmp_dir.to_s, "TEMP" => tmp_dir.to_s, "TMPDIR" => tmp_dir.to_s }
      command = [
        ExecutablePath.resolve("yt-dlp").to_s,
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
        "--ffmpeg-location", Rails.root.join("bin").to_s,
        "--output", AUDIO_DIR.join(isrc).to_s,
        "ytsearch5: #{details.dig("artist", "name")} #{details["title"]} audio"
      ]

      # The exit status is ignored, like in the Laravel app: callers respond
      # with 404 when no file was produced.
      TimedProcess.run(*command, env: env, timeout_seconds: DOWNLOAD_TIMEOUT_SECONDS)
    end

    def match_filter(expected_duration)
      seconds = expected_duration.to_f
      return "age_limit<18" unless seconds.positive?

      window = seconds * DURATION_TOLERANCE
      "age_limit<18 & duration>#{(seconds - window).round} & duration<#{(seconds + window).round}"
    end
  end
end
