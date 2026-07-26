# Search, MP3 fetching/serving and lyrics (port of the Laravel
# SpotifyController).
class SpotifyController < ApiController
  LYRICS_URL = "https://lrclib.net/api/get"

  def search
    query = params[:q].to_s.strip

    return render json: { songs: [], playlists: [] } if query.empty?

    results = SongSearch.search(query)

    render json: {
      songs: format_tracks(results[:tracks]),
      playlists: format_playlists(results[:playlists])
    }
  end

  def get_mp3
    isrc = params[:isrc]
    # ISRCs are alphanumeric; this also keeps the value safe to use in the
    # audio file path below.
    return head :bad_request unless isrc.match?(/\A[a-zA-Z0-9-]+\z/)

    if TalkSegment.talk_id?(isrc)
      # Talk audio is generated, never downloaded: a talk id must not fall
      # through to the Deezer/yt-dlp path.
      return head :not_found unless TalkAudio.ensure_rendered(isrc)
    else
      SongCache.ensure_cached(isrc)
    end
    send_mp3(isrc)
  end

  # Fire-and-forget warmup used by the app for upcoming queue songs: caches
  # the MP3 in the background so pressing play on it later is instant.
  def prepare
    isrc = params[:isrc]
    return head :bad_request unless isrc.match?(/\A[a-zA-Z0-9-]+\z/)

    if TalkSegment.talk_id?(isrc)
      return head :ok if TalkAudio.rendered?(isrc)

      GenerateTalkSegmentJob.perform_later(isrc)
    else
      return head :ok if SongCache.cached?(isrc)

      CacheSongJob.perform_later(isrc)
    end
    head :accepted
  end

  def lyrics
    return talk_lyrics(params[:isrc]) if TalkSegment.talk_id?(params[:isrc])

    song = Song.find(params[:isrc])
    response = fetch_lyrics(song)

    if response["plainLyrics"].nil? && response["syncedLyrics"].nil?
      render json: { error: "Lyrics not found" }, status: :not_found
    else
      render json: response
    end
  end

  private

  def format_tracks(tracks)
    tracks = tracks.select { |track| track["isrc"].present? }

    all_playlists = Playlist.all
    playlist_ids_by_isrc = PlaylistSong.where(song_isrc: tracks.map { |track| track["isrc"] })
      .group_by(&:song_isrc)
      .transform_values { |rows| rows.map(&:playlist_id).to_set }

    tracks.map do |track|
      playlist_ids = playlist_ids_by_isrc[track["isrc"]] || Set.new

      {
        isrc: track["isrc"],
        title: track["title"],
        artist: track.dig("artist", "name"),
        album: track.dig("album", "title"),
        image_url: track.dig("album", "cover_medium") || Song::PLACEHOLDER_IMAGE,
        duration: track["duration"],
        is_in_playlist_map: all_playlists.index_by(&:id).transform_values do |playlist|
          { name: playlist.name, contains: playlist_ids.include?(playlist.id) }
        end
      }
    end
  end

  def format_playlists(playlists)
    playlists.map do |playlist|
      {
        id: "deezer_#{playlist["id"]}",
        name: playlist["title"],
        image_url: playlist["picture_medium"] || Song::PLACEHOLDER_IMAGE,
        track_count: playlist["nb_tracks"],
        author: playlist.dig("user", "name") || "Unknown",
        songs: []
      }
    end
  end

  # A talk segment's "lyrics" are its transcript, so the news text shows up in
  # the player like song lyrics do.
  def talk_lyrics(id)
    segment = TalkSegment.find_by(id: id)
    if segment&.transcript.blank?
      return render json: { error: "Lyrics not found" }, status: :not_found
    end

    render json: {
      "plainLyrics" => segment.transcript,
      "syncedLyrics" => synced_transcript(segment)
    }
  end

  # The ambient/TV view only renders synced lyrics, so spread the transcript's
  # sentences evenly over the segment's duration as coarse LRC lines.
  def synced_transcript(segment)
    sentences = segment.transcript.scan(/[^.!?]+[.!?]*/).map(&:strip).reject(&:empty?)
    return nil if sentences.empty? || segment.duration.to_i.zero?

    step = segment.duration.to_f / sentences.size
    sentences.each_with_index.map do |sentence, index|
      seconds = index * step
      format("[%02d:%05.2f] %s", (seconds / 60).floor, seconds % 60, sentence)
    end.join("\n")
  end

  def fetch_lyrics(song)
    uri = URI(LYRICS_URL)
    # "durration" [sic] mirrors the query the Laravel app sent.
    uri.query = URI.encode_www_form(
      artist_name: song.artist,
      track_name: song.title,
      album_name: song.album,
      durration: song.duration
    )

    JSON.parse(Net::HTTP.get_response(uri).body)
  rescue JSON::ParserError
    {}
  end

  def send_mp3(isrc)
    path = SongCache.path(isrc)

    return head :not_found unless path.file?

    # In production, X-Sendfile is configured so send_file only emits the
    # X-Sendfile header and an empty body: Apache (mod_xsendfile) serves the
    # bytes and handles Range requests itself, freeing the app process at once.
    if Rails.application.config.action_dispatch.x_sendfile_header.present?
      return send_file path, type: "audio/mpeg", disposition: "inline"
    end

    # Dev fallback (no X-Sendfile): serve single-range requests ourselves so
    # clients (AVPlayer) can still seek.
    response.headers["Accept-Ranges"] = "bytes"
    ranges = Rack::Utils.get_byte_ranges(request.headers["Range"], path.size)
    if ranges&.one?
      range = ranges.first
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{path.size}"
      send_data File.binread(path, range.size, range.begin),
        type: "audio/mpeg", disposition: "inline", status: :partial_content
    else
      send_file path, type: "audio/mpeg", disposition: "inline"
    end
  end
end
