require "test_helper"

class KaraokeScoreTest < ActiveSupport::TestCase
  def song
    @song ||= Song.create!(
      isrc: "TEST#{SecureRandom.hex(6).upcase}",
      title: "Test Song", artist: "Test Artist", album: "Test Album",
      image_url: Song::PLACEHOLDER_IMAGE, duration: 180
    )
  end

  def build_score(**attributes)
    KaraokeScore.new({ song_isrc: song.isrc, singer_name: "Lucas", score: 8500 }.merge(attributes))
  end

  test "a performance is stored against its song" do
    score = build_score(accuracy: 0.81)

    assert score.save
    assert_equal song.isrc, score.reload.song_isrc
  end

  test "a score for an unknown song is rejected" do
    score = build_score(song_isrc: "NOPE#{SecureRandom.hex(4).upcase}")

    assert_not score.save
    assert score.errors[:song].present?
  end

  test "singer names are trimmed" do
    score = build_score(singer_name: "  Lucas  ")
    score.save!

    assert_equal "Lucas", score.singer_name
  end

  test "a performance needs a singer and a non-negative score" do
    assert_not build_score(singer_name: " ").valid?
    assert_not build_score(singer_name: "x" * 51).valid?
    assert_not build_score(score: -1).valid?
    assert_not build_score(score: nil).valid?
  end

  test "accuracy is optional but must be a fraction" do
    assert build_score(accuracy: nil).valid?
    assert build_score(accuracy: 0).valid?
    assert build_score(accuracy: 1).valid?
    assert_not build_score(accuracy: 1.2).valid?
    assert_not build_score(accuracy: -0.1).valid?
  end

  test "meta round-trips as a hash" do
    score = build_score(meta: { "line_accuracies" => [ 0.9, 0.5 ], "best_combo" => 7 })
    score.save!

    assert_equal [ 0.9, 0.5 ], score.reload.meta["line_accuracies"]
    assert_equal 7, score.meta["best_combo"]
  end

  test "deleting a song takes its scores with it" do
    build_score.save!

    assert_difference -> { KaraokeScore.count }, -1 do
      song.destroy
    end
  end
end
