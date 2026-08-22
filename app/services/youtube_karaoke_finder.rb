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
    # Downloads a matching karaoke/instrumental upload to out_path (as an
    # mp3) and returns true, or returns false without touching out_path if
    # no good-enough match exists.
    def download(artist:, title:, duration:, out_path:)
      video_id = find_matching_video(artist, title, duration)
      return false unless video_id

      download_video(video_id, out_path)
      out_path.file?
    end

    private

    def find_matching_video(artist, title, expected_duration)
      search_candidates(artist, title).find { |candidate| duration_close_enough?(candidate["duration"], expected_duration) }&.fetch("id", nil)
    end

    def search_candidates(artist, title)
      output = TimedProcess.capture(
        ExecutablePath.resolve("yt-dlp").to_s,
        "--dump-json", "--no-playlist", "--match-filter", "age_limit<18",
        "ytsearch#{SEARCH_COUNT}:#{artist} #{title} karaoke instrumental",
        timeout_seconds: METADATA_TIMEOUT_SECONDS
      )

      output.each_line.filter_map { |line| JSON.parse(line) rescue nil }
    end

    def duration_close_enough?(candidate_duration, expected_duration)
      return false if candidate_duration.to_f.zero? || expected_duration.to_f.zero?

      (candidate_duration.to_f - expected_duration.to_f).abs / expected_duration.to_f <= DURATION_TOLERANCE
    end

    def download_video(video_id, out_path)
      options = [
        ExecutablePath.resolve("yt-dlp").to_s,
        # See YtDlp: no JS runtime means no audio formats are offered at all.
        *YtDlp.media_options,
        "--no-playlist", "--format", "bestaudio/best", "--extract-audio",
        "--audio-format", "mp3", "--audio-quality", "0", "--restrict-filenames",
        "--ffmpeg-location", Rails.root.join("bin").to_s,
        "--output", out_path.to_s.delete_suffix(".mp3")
      ]
      url = "https://www.youtube.com/watch?v=#{video_id}"

      # Same client walk as SongCache: the search above already proved this
      # video exists and matches, so a failure here is the download's own and
      # worth retrying on another client rather than falling back to Demucs's
      # noisier instrumental.
      YtDlp.download_attempts.each do |client_options|
        TimedProcess.run(*options, *client_options, url, timeout_seconds: DOWNLOAD_TIMEOUT_SECONDS)
        break if out_path.file?
      end
    end
  end
end
