require "open3"

# Search, MP3 fetching/serving and lyrics (port of the Laravel
# SpotifyController).
class SpotifyController < ApiController
  AUDIO_DIR = Rails.root.join("storage/audio")
  LYRICS_URL = "https://lrclib.net/api/get"
  DOWNLOAD_TIMEOUT_SECONDS = 180

  def search
    query = params[:q].to_s.strip

    return render json: { songs: [], playlists: [] } if query.empty?

    results = Deezer::Client.search(query)

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

    unless Song.exists?(isrc: isrc)
      details = Deezer::Client.track_details(isrc)
      download_mp3(isrc, details)

      Song.create!(
        isrc: isrc,
        title: details["title"],
        artist: details.dig("artist", "name"),
        image_url: details.dig("album", "cover_medium") || Song::PLACEHOLDER_IMAGE,
        album: details.dig("album", "title"),
        duration: details["duration"]
      )
    end

    send_mp3(isrc)
  end

  def lyrics
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

  def download_mp3(isrc, details)
    tmp_dir = Rails.root.join("tmp/yt-dlp")
    FileUtils.mkdir_p(tmp_dir)
    FileUtils.mkdir_p(AUDIO_DIR)

    env = { "TMP" => tmp_dir.to_s, "TEMP" => tmp_dir.to_s, "TMPDIR" => tmp_dir.to_s }
    command = [
      Rails.root.join("bin/yt-dlp").to_s,
      "--no-playlist",
      "--extract-audio",
      "--audio-format", "mp3",
      "--audio-quality", "0",
      "--restrict-filenames",
      "--no-progress",
      "--match-filter", "age_limit<18",
      "--max-downloads", "1",
      "--ffmpeg-location", Rails.root.join("bin").to_s,
      "--output", AUDIO_DIR.join(isrc).to_s,
      "ytsearch5: #{details.dig("artist", "name")} #{details["title"]} audio"
    ]

    # The exit status is ignored, like in the Laravel app: send_mp3 responds
    # with 404 when no file was produced.
    pid = Process.spawn(env, *command, out: File::NULL, err: File::NULL)
    Timeout.timeout(DOWNLOAD_TIMEOUT_SECONDS) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  def send_mp3(isrc)
    path = AUDIO_DIR.join("#{isrc}.mp3")

    return head :not_found unless path.file?

    response.headers["Accept-Ranges"] = "bytes"

    # Serve single-range requests ourselves so clients (AVPlayer) can seek;
    # Laravel's BinaryFileResponse did this out of the box.
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
