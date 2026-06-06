require "test_helper"

class SongTest < ActiveSupport::TestCase
  test "uses isrc as primary key" do
    assert_equal "isrc", Song.primary_key
    assert_equal songs(:one), Song.find("USUM71900001")
  end

  test "knows its playlists through playlist_songs" do
    assert_includes songs(:one).playlists, playlists(:favorites)
    assert_empty songs(:two).playlists
  end

  test "destroying a song removes its plays and playlist entries" do
    song = songs(:one)

    assert_difference("Play.count", -2) do
      assert_difference("PlaylistSong.count", -1) do
        song.destroy
      end
    end
  end
end
