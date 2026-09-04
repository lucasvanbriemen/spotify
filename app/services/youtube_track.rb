# A YouTube video treated as a track.
#
# Search is keyed on ISRCs everywhere in this app — the audio cache, the
# karaoke artifacts, the queue, the scores — so a YouTube video is given a
# pseudo-ISRC ("yt-" + the eleven-character video id), exactly the way
# TalkSegment gives generated speech a "talk-" one. Everything downstream keys
# off that string without knowing where the audio came from; only SongCache
# (which downloads the video instead of searching for it) and the lyrics
# lookup (which has no Deezer row to read) branch on it.
#
# Only URLs the user pasted reach here, and only the video id is ever taken
# out of one — the URL handed to yt-dlp is rebuilt from that id, so nothing
# from the query string reaches the command line.
class YoutubeTrack
  ISRC_PREFIX = "yt-"
  VIDEO_ID = /[A-Za-z0-9_-]{11}/
  ISRC_FORMAT = /\A#{ISRC_PREFIX}#{VIDEO_ID}\z/o

  # youtu.be/ID, youtube.com/watch?v=ID, /shorts/ID, /embed/ID, /live/ID, with
  # or without a scheme, "www." or "music.". Anchored at the host so a song
  # title that merely contains "youtu.be" isn't read as a link.
  URL_PATTERN = %r{
    \A(?:https?://)?(?:[\w-]+\.)*
    (?:
      youtu\.be/(#{VIDEO_ID})
      | youtube\.com/(?:watch\?(?:[^\s]*&)?v=(#{VIDEO_ID})|(?:shorts|embed|live|v)/(#{VIDEO_ID}))
    )
  }xo

  METADATA_TIMEOUT_SECONDS = 30
  DOWNLOAD_TIMEOUT_SECONDS = 300
  # Video metadata (title, channel, length) does not change; the only reason
  # to expire it at all is a video that gets replaced or taken down.
  METADATA_CACHE_TTL = 30.days

  # "(Official Video)", "[Lyrics]", "(HD)" and the rest of the decoration
  # uploaders put in a title. Dropped so the artist/title reaching LRCLIB is
  # the song's, not the upload's.
  TITLE_NOISE = /
    \s*[\(\[]\s*
    (?:official|officiel|official\s+music|music|lyrics?|lyric|audio|visuali[sz]er|hd|hq|4k|full|new|explicit|clip)
    [^\)\]]*[\)\]]
  /xi
  # A trailing "| Official Video" or "- Official Video", the other half of the
  # same habit.
  TRAILING_NOISE = /\s*[|–-]\s*(?:official|lyrics?|audio|hd|4k)\b.*\z/i

  class << self
    def isrc?(isrc)
      isrc.to_s.start_with?(ISRC_PREFIX)
    end

    def isrc_for(video_id)
      "#{ISRC_PREFIX}#{video_id}"
    end

    def video_id_from_isrc(isrc)
      id = isrc.to_s.delete_prefix(ISRC_PREFIX)
      id if id.match?(/\A#{VIDEO_ID}\z/o)
    end

    # The video id a pasted link points at, or nil when the text isn't a
    # YouTube link at all — which is what tells a search to stay a search.
    def video_id_in(query)
      match = URL_PATTERN.match(query.to_s.strip)
      match && match.captures.compact.first
    end

    def url?(query)
      video_id_in(query).present?
    end

    def url_for(video_id)
      "https://www.youtube.com/watch?v=#{video_id}"
    end

    # A Deezer-shaped track hash, so search results, the queue and the karaoke
    # rows can draw a YouTube video without knowing it is one. nil when the
    # video can't be read (private, removed, or yt-dlp is unavailable).
    def track(video_id)
      metadata = metadata(video_id)
      return nil unless metadata

      artist, title = artist_and_title(metadata)

      {
        "isrc" => isrc_for(video_id),
        "title" => title,
        "duration" => metadata["duration"].to_i,
        "artist" => { "name" => artist },
        "album" => {
          "title" => metadata["album"].presence || "YouTube",
          "cover_medium" => metadata["thumbnail"].presence || thumbnail_url(video_id)
        },
        "source" => "youtube",
        "youtube_url" => url_for(video_id)
      }
    end

    # Same shape, addressed by the pseudo-ISRC — what SongCache needs to write
    # a Song row and what the lyrics endpoint needs to query LRCLIB.
    def track_details(isrc)
      video_id = video_id_from_isrc(isrc)
      video_id && track(video_id)
    end

    # Stages the video's audio as an mp3 called `name` in the session. Unlike
    # SongCache's search-and-pick, the video is named outright, so there is no
    # duration window to satisfy — the singer already chose which upload they
    # meant. The caller fetches it out of the session; where the session lives
    # is not this method's business.
    def download(session:, isrc:, name:)
      video_id = video_id_from_isrc(isrc)
      return false unless video_id

      options = [
        session.tool("yt-dlp"),
        # Without a JavaScript runtime YouTube withholds every audio format —
        # see YtDlp.
        *YtDlp.media_options,
        "--no-playlist",
        "--format", "bestaudio/best",
        "--concurrent-fragments", "4",
        "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0",
        "--restrict-filenames", "--no-progress",
        "--ffmpeg-location", session.bin_dir,
        "--output", session.path(name.delete_suffix(".mp3"))
      ]

      YtDlp.download_attempts.each do |client_options|
        result = session.run(
          *options, *client_options, url_for(video_id),
          outputs: [ name ], timeout_seconds: DOWNLOAD_TIMEOUT_SECONDS
        )
        return true if result.produced?(name)
      end

      false
    end

    # Splits "Artist - Title (Official Video)" the way an uploader wrote it.
    # yt-dlp's own music metadata is preferred when the upload carries it
    # (YouTube Music and Art Tracks do), since it is the same data LRCLIB is
    # keyed on.
    def artist_and_title(metadata)
      cleaned = clean_title(metadata["title"].to_s)
      channel = channel_name(metadata)

      return [ metadata["artist"].to_s.split(/\s*[,;]\s*/).first.presence || channel, metadata["track"] ] if metadata["track"].present?

      artist, separator, title = cleaned.partition(/\s+[-–—]\s+/)
      return [ channel, cleaned.presence || "YouTube video" ] if separator.empty? || title.blank?

      [ artist.strip, title.strip ]
    end

    private

    # Left on this host, unlike the download above. Metadata extraction is not
    # behind the JavaScript challenge and is not the thing YouTube 403s, so it
    # has nothing to gain from the GPU box's address — and it sits on the
    # interactive path, where a sleeping desktop would only add latency to
    # somebody pasting a link.
    def metadata(video_id)
      # skip_nil: a yt-dlp hiccup must not cache "this video doesn't exist"
      # for a month — the next paste of the same link should try again.
      Rails.cache.fetch("youtube_track/v1/#{video_id}", expires_in: METADATA_CACHE_TTL, skip_nil: true) do
        output = TimedProcess.capture(
          ExecutablePath.resolve("yt-dlp").to_s,
          "--dump-single-json", "--no-playlist", "--skip-download",
          url_for(video_id),
          timeout_seconds: METADATA_TIMEOUT_SECONDS
        )
        parsed = JSON.parse(output) rescue nil
        parsed if parsed.is_a?(Hash) && parsed["title"].present?
      end
    end

    def channel_name(metadata)
      name = metadata["uploader"].presence || metadata["channel"].presence || "YouTube"
      # "Adele - Topic" is how YouTube names an auto-generated artist channel.
      name.sub(/\s*-\s*Topic\z/i, "").strip
    end

    def clean_title(title)
      title.gsub(TITLE_NOISE, "").sub(TRAILING_NOISE, "").gsub(/\s+/, " ").strip
    end

    def thumbnail_url(video_id)
      "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg"
    end
  end
end
