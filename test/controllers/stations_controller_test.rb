require "test_helper"

class StationsControllerTest < ActionDispatch::IntegrationTest
  test "lists stations with the fields the app decodes" do
    get "/api/stations", headers: AUTH_HEADERS

    assert_response :success
    stations = JSON.parse(response.body)["stations"]
    assert stations.any?

    rock = stations.find { |station| station["id"] == "genre-rock" }
    assert_equal "Rock", rock["name"]
    assert rock["language"].present?
    assert rock["image_url"].present?
  end

  test "builds a queue chunk for a station" do
    get "/api/station/genre-rock/queue", params: { count: 5 }, headers: AUTH_HEADERS

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "genre-rock", body["station"]["id"]
    assert_operator body["items"].size, :>=, 5
    assert(body["items"].all? { |item| %w[song talk].include?(item["kind"]) })
  end

  test "clamps the requested count" do
    get "/api/station/genre-rock/queue", params: { count: 999 }, headers: AUTH_HEADERS

    assert_response :success
    assert_operator JSON.parse(response.body)["items"].size, :<=, 25 + 10 # songs + interleaved talk
  end

  test "404s on unknown stations" do
    get "/api/station/genre-nope/queue", headers: AUTH_HEADERS

    assert_response :not_found
  end
end
