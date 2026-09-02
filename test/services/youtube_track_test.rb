require "test_helper"

class YoutubeTrackTest < ActiveSupport::TestCase
  test "recognises the shapes a YouTube link is pasted in" do
    {
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "http://youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4" => "dQw4w9WgXcQ",
      "https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "https://youtu.be/dQw4w9WgXcQ?t=42" => "dQw4w9WgXcQ",
      "youtu.be/dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "https://music.youtube.com/watch?v=dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "https://www.youtube.com/shorts/dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "https://www.youtube.com/embed/dQw4w9WgXcQ" => "dQw4w9WgXcQ",
      "  https://youtu.be/a_b-c1234XY  " => "a_b-c1234XY"
    }.each do |url, expected|
      assert_equal expected, YoutubeTrack.video_id_in(url), url
    end
  end

  test "an ordinary search is not a link" do
    [ "bohemian rhapsody", "youtube killed the radio star", "https://example.com/watch?v=dQw4w9WgXcQ", "", nil ].each do |query|
      assert_nil YoutubeTrack.video_id_in(query), query.inspect
    end
  end

  test "a video id round-trips through its pseudo-ISRC" do
    isrc = YoutubeTrack.isrc_for("a_b-c1234XY")

    assert_equal "yt-a_b-c1234XY", isrc
    assert YoutubeTrack.isrc?(isrc)
    assert_equal "a_b-c1234XY", YoutubeTrack.video_id_from_isrc(isrc)
    # A real ISRC must never be mistaken for one of ours.
    assert_not YoutubeTrack.isrc?("USRC17607839")
    assert_nil YoutubeTrack.video_id_from_isrc("yt-../../etc/passwd")
  end

  test "splits an uploader's title into an artist and a song" do
    assert_equal [ "a-ha", "Take On Me" ],
      YoutubeTrack.artist_and_title("title" => "a-ha - Take On Me (Official Video)", "uploader" => "a-ha")
    assert_equal [ "Queen", "Bohemian Rhapsody" ],
      YoutubeTrack.artist_and_title("title" => "Queen – Bohemian Rhapsody [Official Music Video]", "uploader" => "Queen Official")
    assert_equal [ "Adele", "Hello" ],
      YoutubeTrack.artist_and_title("title" => "Hello", "uploader" => "Adele - Topic")
  end

  test "prefers the video's own music metadata over its title" do
    assert_equal [ "Dua Lipa", "Levitating" ], YoutubeTrack.artist_and_title(
      "title" => "Levitating (Official Music Video)", "track" => "Levitating", "artist" => "Dua Lipa, DaBaby", "uploader" => "DuaLipaVEVO"
    )
  end

  test "a title with nothing to split falls back to the channel" do
    assert_equal [ "Some Channel", "an untitled jam" ],
      YoutubeTrack.artist_and_title("title" => "an untitled jam", "uploader" => "Some Channel")
  end
end
