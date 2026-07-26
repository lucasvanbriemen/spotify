require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "plays for talk segments are acknowledged but never persisted" do
    assert_no_difference "Play.count" do
      post "/api/plays",
        params: { isrc: "talk-news-nl-2026072608", seconds_played: 45 },
        headers: AUTH_HEADERS
    end

    assert_response :no_content
  end

  test "song plays persist their station attribution" do
    post "/api/plays",
      params: { isrc: songs(:rock_0).isrc, seconds_played: 120, station_id: "genre-rock" },
      headers: AUTH_HEADERS

    assert_response :created
    assert_equal "genre-rock", Play.last.station_id
  end

  test "plays without a station stay unattributed" do
    post "/api/plays",
      params: { isrc: songs(:rock_0).isrc, seconds_played: 120 },
      headers: AUTH_HEADERS

    assert_response :created
    assert_nil Play.last.station_id
  end

  test "stats expose worker health" do
    get "/api/stats", headers: AUTH_HEADERS

    assert_response :success
    assert_includes JSON.parse(response.body).keys, "queue_healthy"
  end
end
