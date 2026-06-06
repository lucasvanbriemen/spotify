require "test_helper"

class SpotifyControllerTest < ActionDispatch::IntegrationTest
  test "search returns empty lists for a blank query" do
    get "/api/search", params: { q: "  " }

    assert_response :success
    assert_equal({ "songs" => [], "playlists" => [] }, response.parsed_body)
  end

  test "search maps tracks and playlists, skipping tracks without an isrc" do
    stub_request(:get, "https://api.deezer.com/search/track?q=test&limit=100")
      .to_return(body: { data: [
        {
          "isrc" => "USUM71900001",
          "title" => "Song One",
          "duration" => 200,
          "artist" => { "name" => "Artist One" },
          "album" => { "title" => "Album One" }
        },
        { "isrc" => "", "title" => "No Isrc" }
      ] }.to_json)
    stub_request(:get, "https://api.deezer.com/search/playlist?q=test&limit=25")
      .to_return(body: { data: [
        { "id" => 42, "title" => "Mix", "nb_tracks" => 10, "picture_medium" => "https://example.com/mix.jpg" }
      ] }.to_json)

    get "/api/search", params: { q: "test" }

    assert_response :success
    body = response.parsed_body

    assert_equal 1, body["songs"].size
    song = body["songs"].first
    assert_equal "USUM71900001", song["isrc"]
    assert_equal "Artist One", song["artist"]
    assert_equal "Album One", song["album"]
    # No cover_medium in the payload, so the placeholder is used.
    assert_equal Song::PLACEHOLDER_IMAGE, song["image_url"]

    # Every local playlist appears in the map; the song is in favorites only.
    map = song["is_in_playlist_map"]
    assert_equal({ "name" => "Favorites", "contains" => true }, map[playlists(:favorites).id.to_s])
    assert_equal({ "name" => "Workout", "contains" => false }, map[playlists(:workout).id.to_s])

    assert_equal [
      {
        "id" => "deezer_42",
        "name" => "Mix",
        "image_url" => "https://example.com/mix.jpg",
        "track_count" => 10,
        "author" => "Unknown",
        "songs" => []
      }
    ], body["playlists"]
  end

  test "lyrics passes the lrclib response through" do
    stub_request(:get, "https://lrclib.net/api/get")
      .with(query: {
        artist_name: "Artist One",
        track_name: "Song One",
        album_name: "Album One",
        durration: "200"
      })
      .to_return(body: { "plainLyrics" => "La la la" }.to_json)

    get "/api/song/USUM71900001/lyrics"

    assert_response :success
    assert_equal "La la la", response.parsed_body["plainLyrics"]
  end

  test "lyrics responds 404 when lrclib has no lyrics" do
    stub_request(:get, "https://lrclib.net/api/get")
      .with(query: hash_including({}))
      .to_return(status: 404, body: { "message" => "not found" }.to_json)

    get "/api/song/USUM71900001/lyrics"

    assert_response :not_found
    assert_equal "Lyrics not found", response.parsed_body["error"]
  end

  test "get_mp3 serves the cached file for a known song" do
    with_audio_file("USUM71900001") do
      get "/api/get-mp3/USUM71900001"

      assert_response :success
      assert_equal "audio/mpeg", response.media_type
      assert_equal "bytes", response.headers["Accept-Ranges"]
      assert_equal "fake mp3 bytes", response.body
    end
  end

  test "get_mp3 serves a partial response for range requests" do
    with_audio_file("USUM71900001") do
      get "/api/get-mp3/USUM71900001", headers: { "Range" => "bytes=0-3" }

      assert_response :partial_content
      assert_equal "fake", response.body
      assert_equal "bytes 0-3/14", response.headers["Content-Range"]
    end
  end

  test "get_mp3 responds 404 when the file is missing" do
    FileUtils.rm_f(SpotifyController::AUDIO_DIR.join("USUM71900001.mp3"))

    get "/api/get-mp3/USUM71900001"

    assert_response :not_found
  end

  private

  def with_audio_file(isrc)
    FileUtils.mkdir_p(SpotifyController::AUDIO_DIR)
    path = SpotifyController::AUDIO_DIR.join("#{isrc}.mp3")
    File.binwrite(path, "fake mp3 bytes")

    yield
  ensure
    FileUtils.rm_f(path)
  end
end
