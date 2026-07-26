require "test_helper"

class StationTest < ActiveSupport::TestCase
  test "genre stations appear only with enough songs" do
    ids = Station.all.map(&:id)

    assert_includes ids, "genre-rock" # 16 songs
    assert_not_includes ids, "genre-jazz" # 1 song
  end

  test "decade stations appear only with enough songs" do
    ids = Station.all.map(&:id)

    assert_includes ids, "decade-80s"
    assert_not_includes ids, "decade-50s" # only the lone jazz song
  end

  test "smart stations appear when they have candidates" do
    ids = Station.all.map(&:id)

    assert_includes ids, "smart-morning"
    assert_includes ids, "smart-party"     # 8 songs with bpm >= 115
    assert_includes ids, "smart-focus"     # bpm <= 110
    assert_includes ids, "smart-discovery" # nothing played twice yet
  end

  test "genre station candidates are scoped to the genre" do
    station = Station.find("genre-rock")

    assert_equal 16, station.candidate_songs.count
    assert station.candidate_songs.all? { |song| song.genre == "Rock" }
  end

  test "decade station candidates are scoped to the decade" do
    station = Station.find("decade-80s")

    assert station.candidate_songs.all? { |song| (1980..1989).cover?(song.release_year) }
  end

  test "focus station carries no news, discovery only intros" do
    assert_not Station.find("smart-focus").news?
    assert_not Station.find("smart-focus").intros?
    assert_not Station.find("smart-discovery").news?
    assert Station.find("smart-discovery").intros?
    assert Station.find("genre-rock").news?
  end

  test "find raises on unknown station" do
    assert_raises(Station::NotFound) { Station.find("genre-nope") }
  end

  test "stations serialize with the fields the app decodes" do
    json = Station.find("genre-rock").as_json

    assert_equal "genre-rock", json[:id]
    assert_equal "Rock", json[:name]
    assert json[:language].present?
    assert json[:song_count].positive?
    assert json[:image_url].present?
  end
end
