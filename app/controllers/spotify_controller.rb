# Search, MP3 fetching/serving and lyrics (port of the Laravel
# SpotifyController).
class SpotifyController < ApiController
  include ServesAudio

  def search
    query = params[:q].to_s.strip

    return render json: { songs: [], playlists: [] } if query.empty?

    results = SongSearch.search(query)

    render json: {
      songs: format_tracks(results[:tracks]),
      playlists: format_playlists(results[:playlists])
    }
  end

  # Same as #search, but only for tracks LRCLIB confirms have synced
  # (line-timed) lyrics — the karaoke UI has nothing to highlight otherwise.
  def karaoke_search
    query = params[:q].to_s.strip

    return render json: { songs: [] } if query.empty?

    render json: { songs: format_tracks(KaraokeSearch.search(query)) }
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

    attrs = lyrics_lookup_attrs(params[:isrc])
    return render json: { error: "Lyrics not found" }, status: :not_found unless attrs

    response = Lrclib::Client.fetch(**attrs)

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

  # A Song row only exists once the track has been played (or added to a
  # playlist) at least once — see SongCache.ensure_cached. The karaoke UI
  # fetches lyrics and starts playback in parallel, so lyrics can't assume
  # that row is there yet; fall back to a live Deezer lookup for the same
  # artist/title/album/duration LRCLIB needs.
  def lyrics_lookup_attrs(isrc)
    if (song = Song.find_by(isrc: isrc))
      { artist: song.artist, title: song.title, album: song.album, duration: song.duration }
    else
      details = Deezer::Client.track_details(isrc)
      # An unknown ISRC comes back as 200 OK with an error body, not a
      # non-OK response Deezer::Client would raise on — so check for the
      # track data itself before treating this as a hit.
      return nil if details["title"].blank?

      { artist: details.dig("artist", "name"), title: details["title"], album: details.dig("album", "title"), duration: details["duration"] }
    end
  rescue Deezer::Client::Error
    nil
  end

  def send_mp3(isrc)
    send_audio_file(SongCache.path(isrc))
  end
end
