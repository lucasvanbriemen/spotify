require "test_helper"

class PlaylistTest < ActiveSupport::TestCase
  test "knows its songs through playlist_songs" do
    assert_equal [ songs(:one) ], playlists(:favorites).songs.to_a
    assert_empty playlists(:workout).songs
  end

  test "a song cannot be added to the same playlist twice" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      playlists(:favorites).playlist_songs.create!(song_isrc: "USUM71900001")
    end
  end
end
