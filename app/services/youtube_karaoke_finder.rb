# Looks for an existing karaoke/instrumental upload of a song on YouTube.
# These are almost always better-mastered than an AI-separated instrumental
# (no artifacts from splitting the mix back apart), so VocalSeparation
# prefers one when a good match exists and only falls back to Demucs's own
# output otherwise.
class YoutubeKaraokeFinder
  SEARCH_COUNT = 5
  # A result whose duration is way off the original isn't a matching
  # karaoke version — it's a different edit, a compilation, or unrelated.
  DURATION_TOLERANCE = 0.15
  METADATA_TIMEOUT_SECONDS = 30
  DOWNLOAD_TIMEOUT_SECONDS = 180

  class << self
    # Stages a matching karaoke/instrumental upload in the session as `name`
    # and returns true, or returns false having staged nothing if no
    # good-enough match exists.
    #
    # The session is the caller's, not one of ours: VocalSeparation runs this
    # concurrently with the separation and both want their results in the same
    # scratch directory, so that the alignment check between them is a local
    # read on whichever host did the work.
    def download(session:, artist:, title:, duration:, name:)
      video_id = find_matching_video(session, artist, title, duration)
      return false unless video_id

      download_video(session, video_id, name)
    end

    private

    def find_matching_video(session, artist, title, expected_duration)
      search_candidates(session, artist, title)
        .find { |candidate| duration_close_enough?(candidate["duration"], expected_duration) }
        &.fetch("id", nil)
    end

    def search_candidates(session, artist, title)
      result = session.run(
        session.tool("yt-dlp"),
        # The id and the length are the only two fields the match below reads,
        # and --print answers in a line each. --dump-json answered with the
        # whole extractor payload — tens of kilobytes per result — which does
        # not survive the bounded output a session brings back from a remote
        # host, and was never read.
        "--print", "%(id)s\t%(duration)s",
        "--no-playlist", "--match-filter", "age_limit<18",
        "ytsearch#{SEARCH_COUNT}:#{artist} #{title} karaoke instrumental",
        timeout_seconds: METADATA_TIMEOUT_SECONDS
      )

      result.stdout.each_line.filter_map do |line|
        id, duration = line.strip.split("\t")
        { "id" => id, "duration" => duration.to_f } if id.present?
      end
    end

    def duration_close_enough?(candidate_duration, expected_duration)
      return false if candidate_duration.to_f.zero? || expected_duration.to_f.zero?

      (candidate_duration.to_f - expected_duration.to_f).abs / expected_duration.to_f <= DURATION_TOLERANCE
    end

    def download_video(session, video_id, name)
      options = [
        session.tool("yt-dlp"),
        # See YtDlp: no JS runtime means no audio formats are offered at all.
        *YtDlp.media_options,
        "--no-playlist", "--format", "bestaudio/best", "--extract-audio",
        "--audio-format", "mp3", "--audio-quality", "0", "--restrict-filenames",
        "--ffmpeg-location", session.bin_dir,
        # yt-dlp appends the audio format's extension itself, so the template
        # is the name without it.
        "--output", session.path(name.delete_suffix(".mp3"))
      ]
      url = "https://www.youtube.com/watch?v=#{video_id}"

      # Same client walk as SongCache: the search above already proved this
      # video exists and matches, so a failure here is the download's own and
      # worth retrying on another client rather than falling back to Demucs's
      # noisier instrumental.
      YtDlp.download_attempts.each do |client_options|
        result = session.run(
          *options, *client_options, url,
          outputs: [ name ], timeout_seconds: DOWNLOAD_TIMEOUT_SECONDS
        )
        return true if result.produced?(name)
      end

      false
    end
  end
end
