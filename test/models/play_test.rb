require "test_helper"

class PlayTest < ActiveSupport::TestCase
  test "belongs to a song" do
    assert_equal songs(:one), plays(:one_first).song
  end

  test "requires an existing song" do
    play = Play.new(song_isrc: "ZZZZZ0000000", seconds_played: 10)

    assert_not play.valid?
    assert play.errors[:song].any?
  end

  test "requires seconds_played to be a positive integer" do
    assert_not Play.new(song_isrc: "USUM71900001", seconds_played: 0).valid?
    assert_not Play.new(song_isrc: "USUM71900001", seconds_played: 1.5).valid?
    assert Play.new(song_isrc: "USUM71900001", seconds_played: 1).valid?
  end
end
