require "test_helper"
require "minitest/mock"

# A pasted YouTube link is not a query to rank — it is the one track the user
# already picked, so it bypasses iTunes, Deezer and (for karaoke) the
# synced-lyrics filter alike. Everything else must still go the normal way.
class SongSearchTest < ActiveSupport::TestCase
  URL = "https://youtu.be/dQw4w9WgXcQ".freeze

  def youtube_track
    {
      "isrc" => "yt-dQw4w9WgXcQ",
      "title" => "Never Gonna Give You Up",
      "duration" => 213,
      "artist" => { "name" => "Rick Astley" },
      "album" => { "title" => "YouTube", "cover_medium" => "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" }
    }
  end

  test "a pasted link is the only result, with no playlists beside it" do
    results = YoutubeTrack.stub(:track, youtube_track) { SongSearch.search(URL) }

    assert_equal [ "yt-dQw4w9WgXcQ" ], results[:tracks].map { |track| track["isrc"] }
    assert_empty results[:playlists]
  end

  test "a link that cannot be read is not cached as an empty search" do
    calls = 0
    resolver = ->(_video_id) { calls += 1; nil }

    2.times { YoutubeTrack.stub(:track, resolver) { assert_empty SongSearch.search(URL)[:tracks] } }

    assert_equal 2, calls, "the next paste of the same link must try again"
  end

  test "karaoke search shows a pasted link whether or not LRCLIB knows the song" do
    # No stub on Lrclib::Client at all: reaching it would be the bug.
    tracks = YoutubeTrack.stub(:track, youtube_track) { KaraokeSearch.search(URL) }

    assert_equal [ "yt-dQw4w9WgXcQ" ], tracks.map { |track| track["isrc"] }
  end

  test "karaoke results shape a pasted link the way a result row draws one" do
    # Readiness is read off the disk cache, which a previous run may have
    # filled; what matters here is that the annotation is applied at all.
    result = VocalSeparation.stub(:ready?, true) do
      YoutubeTrack.stub(:track, youtube_track) { KaraokeSearch.results(URL) }
    end.sole

    assert_equal "yt-dQw4w9WgXcQ", result[:isrc]
    assert_equal "Never Gonna Give You Up", result[:title]
    assert_equal "Rick Astley", result[:artist]
    assert_equal true, result[:ready]
  end
end
