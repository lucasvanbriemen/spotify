# Local playlists plus read-through to Deezer playlists (port of the Laravel
# PlaylistController). Local playlist ids are prefixed "local_" in the index
# so the frontend can tell them apart from "deezer_" ones.
class PlaylistsController < ApiController
  def index
    playlists = Playlist.all.map do |playlist|
      playlist.as_json.merge("id" => "local_#{playlist.id}")
    end

    render json: playlists
  end

  def show
    if params[:id].start_with?("local_")
      show_local
    else
      show_deezer
    end
  end

  def add_song
    details = Deezer::Client.track_details(params[:isrc])

    song = Song.find_or_initialize_by(isrc: params[:isrc])
    song.update!(
      title: details["title"] || "",
      artist: details.dig("artist", "name") || "",
      album: details.dig("album", "title") || "",
      image_url: details.dig("album", "cover_medium") || "",
      duration: details["duration"] || 0
    )

    playlist = Playlist.find(params[:id])
    # Attach without duplicating (the Laravel app used syncWithoutDetaching).
    playlist.playlist_songs.find_or_create_by!(song_isrc: song.isrc)

    render json: song
  end

  private

  def show_local
    playlist = Playlist.find(params[:id].delete_prefix("local_"))
    all_playlists = Playlist.includes(:songs).to_a

    songs = playlist.songs.map do |song|
      song.as_json.merge("is_in_playlist_map" => playlist_map(all_playlists) { |p| p.songs.include?(song) })
    end

    render json: playlist.as_json.merge("songs" => songs)
  end

  def show_deezer
    deezer_playlist = Deezer::Client.playlist_details(params[:id].delete_prefix("deezer_"))
    all_playlists = Playlist.includes(:songs).to_a

    songs = deezer_playlist.dig("tracks", "data").map do |track|
      isrc = track["isrc"]

      {
        isrc: isrc,
        title: track["title"],
        artist: track.dig("artist", "name"),
        album: track.dig("album", "title"),
        image_url: track.dig("album", "cover_medium"),
        duration: track["duration"],
        is_in_playlist_map: playlist_map(all_playlists) { |p| p.songs.any? { |song| song.isrc == isrc } }
      }
    end

    render json: {
      id: "deezer_#{deezer_playlist["id"]}",
      name: deezer_playlist["title"] || "",
      image_url: deezer_playlist["picture_medium"] || "",
      songs: songs
    }
  end

  # { <playlist id> => { name:, image_url:, contains: } } for every local
  # playlist; the block decides containment.
  def playlist_map(all_playlists)
    all_playlists.each_with_object({}) do |playlist, map|
      map[playlist.id] = {
        name: playlist.name,
        image_url: playlist.image_url,
        contains: yield(playlist)
      }
    end
  end
end
