require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "store_play records a play" do
    assert_difference("Play.count", 1) do
      post "/api/plays", params: { isrc: "USUM71900001", seconds_played: 42 }
    end

    assert_response :created
    body = response.parsed_body
    assert_kind_of Integer, body["id"]
    assert_equal "USUM71900001", body["song_isrc"]
    assert_equal 42, body["seconds_played"]
  end

  test "store_play rejects an unknown isrc" do
    assert_no_difference("Play.count") do
      post "/api/plays", params: { isrc: "ZZZZZ0000000", seconds_played: 42 }
    end

    assert_response :unprocessable_entity
  end

  test "store_play rejects non-positive seconds_played" do
    assert_no_difference("Play.count") do
      post "/api/plays", params: { isrc: "USUM71900001", seconds_played: 0 }
    end

    assert_response :unprocessable_entity
  end

  test "index aggregates plays" do
    get "/api/stats"

    assert_response :success
    body = response.parsed_body

    assert_equal 3, body["total_plays"]
    assert_equal 2, body["unique_songs"]
    assert_equal 260, body["total_seconds_played"]

    assert_equal [
      {
        "isrc" => "USUM71900001",
        "title" => "Song One",
        "artist" => "Artist One",
        "image_url" => "https://example.com/covers/one.jpg",
        "play_count" => 2,
        "seconds_played" => 200
      },
      {
        "isrc" => "GBUM72000002",
        "title" => "Song Two",
        "artist" => "Artist Two",
        "image_url" => "https://example.com/covers/two.jpg",
        "play_count" => 1,
        "seconds_played" => 60
      }
    ], body["top_songs"]
  end
end
