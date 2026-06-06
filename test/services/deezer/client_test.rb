require "test_helper"

module Deezer
  class ClientTest < ActiveSupport::TestCase
    test "search queries tracks and playlists" do
      stub_request(:get, "https://api.deezer.com/search/track?q=test&limit=100")
        .to_return(body: { data: [ { "title" => "Track" } ] }.to_json)
      stub_request(:get, "https://api.deezer.com/search/playlist?q=test&limit=25")
        .to_return(body: { data: [ { "title" => "List" } ] }.to_json)

      results = Client.search("test")

      assert_equal [ { "title" => "Track" } ], results[:tracks]
      assert_equal [ { "title" => "List" } ], results[:playlists]
    end

    test "search returns empty lists when a request fails" do
      stub_request(:get, "https://api.deezer.com/search/track?q=test&limit=100").to_return(status: 500)
      stub_request(:get, "https://api.deezer.com/search/playlist?q=test&limit=25").to_timeout

      results = Client.search("test")

      assert_equal [], results[:tracks]
      assert_equal [], results[:playlists]
    end

    test "track_details fetches a track by isrc" do
      stub_request(:get, "https://api.deezer.com/track/isrc:USUM71900001")
        .to_return(body: { "title" => "Song One" }.to_json)

      assert_equal({ "title" => "Song One" }, Client.track_details("USUM71900001"))
    end

    test "track_details raises when the request fails" do
      stub_request(:get, "https://api.deezer.com/track/isrc:USUM71900001").to_return(status: 404)

      assert_raises(Client::Error) { Client.track_details("USUM71900001") }
    end

    test "playlist_details fetches a playlist by id" do
      stub_request(:get, "https://api.deezer.com/playlist/123")
        .to_return(body: { "id" => 123, "title" => "List" }.to_json)

      assert_equal({ "id" => 123, "title" => "List" }, Client.playlist_details(123))
    end
  end
end
