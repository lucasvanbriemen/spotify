require "test_helper"

class PlaylistsControllerTest < ActionDispatch::IntegrationTest
  test "index prefixes local playlist ids" do
    get "/api/playlists"

    assert_response :success
    ids = response.parsed_body.map { |playlist| playlist["id"] }
    assert_includes ids, "local_#{playlists(:favorites).id}"
    assert_includes ids, "local_#{playlists(:workout).id}"
  end

  test "show returns a local playlist with songs and playlist map" do
    get "/api/playlist/local_#{playlists(:favorites).id}"

    assert_response :success
    body = response.parsed_body

    assert_equal playlists(:favorites).id, body["id"]
    assert_equal "Favorites", body["name"]
    assert_equal 1, body["songs"].size

    song = body["songs"].first
    assert_equal "USUM71900001", song["isrc"]

    map = song["is_in_playlist_map"]
    assert_equal true, map[playlists(:favorites).id.to_s]["contains"]
    assert_equal false, map[playlists(:workout).id.to_s]["contains"]
    assert_equal "https://example.com/playlists/favorites.jpg", map[playlists(:favorites).id.to_s]["image_url"]
  end

  test "show responds 404 for an unknown local playlist" do
    get "/api/playlist/local_999999"

    assert_response :not_found
  end

  test "show returns a deezer playlist with local containment info" do
    stub_request(:get, "https://api.deezer.com/playlist/42")
      .to_return(body: {
        "id" => 42,
        "title" => "Mix",
        "picture_medium" => "https://example.com/mix.jpg",
        "tracks" => { "data" => [
          {
            "isrc" => "USUM71900001",
            "title" => "Song One",
            "duration" => 200,
            "artist" => { "name" => "Artist One" },
            "album" => { "title" => "Album One", "cover_medium" => "https://example.com/one.jpg" }
          }
        ] }
      }.to_json)

    get "/api/playlist/deezer_42"

    assert_response :success
    body = response.parsed_body

    assert_equal "deezer_42", body["id"]
    assert_equal "Mix", body["name"]

    song = body["songs"].first
    assert_equal "USUM71900001", song["isrc"]
    assert_equal true, song["is_in_playlist_map"][playlists(:favorites).id.to_s]["contains"]
  end

  test "add_song upserts the song and attaches it once" do
    stub_request(:get, "https://api.deezer.com/track/isrc:FRXXX2400003")
      .to_return(body: {
        "title" => "New Song",
        "duration" => 240,
        "artist" => { "name" => "New Artist" },
        "album" => { "title" => "New Album", "cover_medium" => "https://example.com/new.jpg" }
      }.to_json)

    assert_difference("Song.count", 1) do
      post "/api/playlist/#{playlists(:favorites).id}/songs", params: { isrc: "FRXXX2400003" }
    end

    assert_response :success
    assert_equal "New Song", response.parsed_body["title"]
    assert_includes playlists(:favorites).songs.reload.map(&:isrc), "FRXXX2400003"

    # Adding the same song again neither duplicates the song nor the link.
    assert_no_difference([ "Song.count", "PlaylistSong.count" ]) do
      post "/api/playlist/#{playlists(:favorites).id}/songs", params: { isrc: "FRXXX2400003" }
    end

    assert_response :success
  end
end
