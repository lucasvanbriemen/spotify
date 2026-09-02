require "test_helper"
require "minitest/mock"

# Authentication talks to the live login service; these tests are about
# search and lyrics, so the check is replaced with a stubbed account.
module SpotifyTestLogin
  def require_login
    @current_account = { "name" => "Tester" }
  end
end
SpotifyController.prepend(SpotifyTestLogin)

# Pasting a YouTube link where a search goes: the whole point is that the rest
# of the app never learns the difference, so these go through the real routes
# and assert on the JSON the iOS app and the karaoke screen actually read.
class SpotifyControllerTest < ActionDispatch::IntegrationTest
  URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ".freeze
  ISRC = "yt-dQw4w9WgXcQ".freeze

  def youtube_track
    {
      "isrc" => ISRC,
      "title" => "Never Gonna Give You Up",
      "duration" => 213,
      "artist" => { "name" => "Rick Astley" },
      "album" => { "title" => "YouTube", "cover_medium" => "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" }
    }
  end

  test "a pasted link comes back as the one search result" do
    YoutubeTrack.stub(:track, youtube_track) { get "/api/search", params: { q: URL } }
    assert_response :success

    body = JSON.parse(response.body)
    song = body["songs"].sole

    assert_equal ISRC, song["isrc"]
    assert_equal "Never Gonna Give You Up", song["title"]
    assert_equal "Rick Astley", song["artist"]
    # The playlist map is what makes a row's "add to playlist" menu work; a
    # YouTube song is a song like any other and must still get one.
    assert song.key?("is_in_playlist_map")
    assert_empty body["playlists"]
  end

  test "the karaoke search shows it too, badged like any other song" do
    # Readiness is read off the disk cache, which a previous run may have
    # filled; what matters here is that the annotation is applied at all.
    VocalSeparation.stub(:ready?, true) do
      YoutubeTrack.stub(:track, youtube_track) { get "/api/karaoke-search", params: { q: URL } }
    end
    assert_response :success

    song = JSON.parse(response.body)["songs"].sole
    assert_equal ISRC, song["isrc"]
    assert_equal true, song["ready"]
  end

  test "a pseudo-ISRC survives the format check the audio routes make" do
    # Underscores are legal in a video id and were not in the old ISRC check,
    # so this is the gate that used to answer 400 for a third of all videos.
    post "/api/get-mp3/yt-a_b-c1234XY/prepare"
    assert_response :accepted

    # And it is still a gate: the value is joined onto a cached-file path.
    post "/api/get-mp3/#{CGI.escape('../../etc/passwd')}/prepare"
    assert_response :bad_request
  end

  test "lyrics for a pasted link are looked up by the video's own artist and title" do
    asked = nil
    lyrics = lambda do |artist:, title:, album:, duration:|
      asked = { artist:, title:, duration: }
      { "plainLyrics" => "We're no strangers to love", "syncedLyrics" => "[00:18.00] We're no strangers to love" }
    end

    YoutubeTrack.stub(:track, youtube_track) do
      Lrclib::Client.stub(:fetch, lyrics) { get "/api/song/#{ISRC}/lyrics" }
    end

    assert_response :success
    assert_equal({ artist: "Rick Astley", title: "Never Gonna Give You Up", duration: 213 }, asked)
    assert_match "no strangers", JSON.parse(response.body)["syncedLyrics"]
  end
end
