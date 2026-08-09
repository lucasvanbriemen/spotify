require "test_helper"

# Exercised through the controller instance rather than as requests: every
# route sits behind the login redirect, and the logic worth testing here is
# the shaping and the personal-best comparison.
class KaraokeScoresControllerTest < ActiveSupport::TestCase
  def song
    @song ||= Song.create!(
      isrc: "TEST#{SecureRandom.hex(6).upcase}",
      title: "Test Song", artist: "Test Artist", album: "Test Album",
      image_url: Song::PLACEHOLDER_IMAGE, duration: 180
    )
  end

  def record(singer_name:, score:)
    KaraokeScore.create!(song_isrc: song.isrc, singer_name: singer_name, score: score)
  end

  def controller_for(isrc)
    controller = KaraokeScoresController.new
    controller.params = ActionController::Parameters.new(isrc: isrc)
    controller
  end

  test "a listed score carries no meta" do
    score = KaraokeScore.create!(song_isrc: song.isrc, singer_name: "Lucas", score: 8500, accuracy: 0.8, meta: { "a" => 1 })

    json = controller_for(song.isrc).send(:score_json, score)

    assert_equal %i[id singer_name score accuracy created_at].sort, json.keys.sort
    assert_equal 8500, json[:score]
  end

  test "the first performance of a song is a personal best" do
    score = record(singer_name: "Lucas", score: 7000)

    assert controller_for(song.isrc).send(:personal_best?, score)
  end

  test "beating your own previous best counts, losing to it does not" do
    record(singer_name: "Lucas", score: 7000)
    better = record(singer_name: "Lucas", score: 9100)
    worse = record(singer_name: "Lucas", score: 4000)

    assert controller_for(song.isrc).send(:personal_best?, better)
    assert_not controller_for(song.isrc).send(:personal_best?, worse)
  end

  test "singers do not compete for each other's personal bests" do
    record(singer_name: "Lucas", score: 9500)
    other = record(singer_name: "Sam", score: 3000)

    assert controller_for(song.isrc).send(:personal_best?, other)
  end

  test "meta is accepted as a plain hash" do
    controller = KaraokeScoresController.new
    controller.params = ActionController::Parameters.new(meta: { "line_accuracies" => [ 0.5, 0.9 ] })

    assert_equal({ "line_accuracies" => [ 0.5, 0.9 ] }, controller.send(:meta_param))
    assert_kind_of Hash, controller.send(:meta_param)
  end

  test "meta is optional" do
    controller = KaraokeScoresController.new
    controller.params = ActionController::Parameters.new({})

    assert_nil controller.send(:meta_param)
  end

  test "history entries carry display fields and preparation state" do
    record(singer_name: "Lucas", score: 8000)
    row = controller_for(song.isrc).send(:grouped_songs, "sing_count DESC").find { |item| item.song_isrc == song.isrc }

    entry = controller_for(song.isrc).send(:history_entry, row, { song.isrc => song })

    assert_equal song.isrc, entry[:isrc]
    assert_equal "Test Song", entry[:title]
    assert_equal 1, entry[:sing_count]
    # Nothing has been separated for this ISRC, so it is a cold song.
    assert_equal false, entry[:ready]
    assert_nil entry[:difficulty]
  end

  test "history tolerates a score whose song row has gone" do
    row = Struct.new(:song_isrc, :sing_count).new("GONE123", 3)

    entry = controller_for(song.isrc).send(:history_entry, row, {})

    assert_equal "Unknown", entry[:title]
    assert_equal "Unknown Artist", entry[:artist]
  end
end
