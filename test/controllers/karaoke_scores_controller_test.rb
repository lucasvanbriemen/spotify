require "test_helper"
require "minitest/mock"

# Authentication talks to the live login service; these tests are about
# scores, so the check is replaced with a stubbed account.
module KaraokeTestLogin
  def require_login
    @current_account = { "name" => "Tester" }
  end
end
KaraokeScoresController.prepend(KaraokeTestLogin)
KaraokeTracksController.prepend(KaraokeTestLogin)

class KaraokeScoresControllerTest < ActionDispatch::IntegrationTest
  ISRC = "TESTKARA001".freeze

  setup do
    @song = Song.create!(
      isrc: ISRC, title: "Test Song", artist: "Tester", album: "Test Album",
      duration: 180, image_url: Song::PLACEHOLDER_IMAGE
    )
  end

  teardown do
    @song.destroy
  end

  test "posting a score answers with the personal-best comparison" do
    post "/api/karaoke/#{ISRC}/scores", params: { singer_name: "Lucas", score: 8000, accuracy: 0.8 }, as: :json
    assert_response :created
    first = JSON.parse(response.body)
    assert first["personal_best"]
    assert_equal 8000, first["best_score"]

    post "/api/karaoke/#{ISRC}/scores", params: { singer_name: "Lucas", score: 6000, accuracy: 0.6 }, as: :json
    assert_response :created
    second = JSON.parse(response.body)
    assert_not second["personal_best"]
    assert_equal 8000, second["best_score"]
  end

  test "the leaderboard groups by singer name and keeps each name's best" do
    { "Lucas" => [ 8000, 6000 ], "Guest" => [ 9000 ] }.each do |name, scores|
      scores.each do |value|
        post "/api/karaoke/#{ISRC}/scores", params: { singer_name: name, score: value }, as: :json
        assert_response :created
      end
    end

    get "/api/karaoke/#{ISRC}/scores"
    assert_response :success
    payload = JSON.parse(response.body)

    best = payload["best"].map { |row| [ row["singer_name"], row["score"] ] }
    assert_equal [ [ "Guest", 9000 ], [ "Lucas", 8000 ] ], best
    assert_equal 3, payload["recent"].length
  end

  test "a malformed isrc is rejected before touching anything" do
    post "/api/karaoke/not%20valid/scores", params: { singer_name: "X", score: 1 }, as: :json
    assert_response :bad_request
  end

  test "a blank singer name is unprocessable" do
    post "/api/karaoke/#{ISRC}/scores", params: { singer_name: "  ", score: 100 }, as: :json
    assert_response :unprocessable_entity
  end

  test "history lists already-prepared songs as ready to sing" do
    VocalSeparation.stub(:prepared_isrcs, [ ISRC, "GONE00000001" ]) do
      get "/api/karaoke-history"
    end
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal 1, payload["ready"].length # the orphaned artifact is left out

    entry = payload["ready"].first
    assert_equal ISRC, entry["isrc"]
    assert_equal "Test Song", entry["title"]
    assert entry["ready"]
  end
end

class KaraokeTracksControllerTest < ActionDispatch::IntegrationTest
  test "status for an unprepared song reports its stage without an artifacts payload" do
    get "/api/karaoke/UNPREPARED01/status"
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal false, payload["ready"]
    assert_includes %w[downloading separating failed], payload["stage"]
    assert_nil payload["alignment_offset_seconds"]
  end
end
