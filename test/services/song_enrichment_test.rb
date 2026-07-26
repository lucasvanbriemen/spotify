require "test_helper"

class SongEnrichmentTest < ActiveSupport::TestCase
  test "maps a full Deezer track payload" do
    attrs = SongEnrichment.attributes_from_track(
      "bpm" => 120.5, "release_date" => "1985-07-13", "rank" => 750000
    )

    assert_equal 120.5, attrs[:bpm]
    assert_equal 1985, attrs[:release_year]
    assert_equal 750000, attrs[:deezer_rank]
  end

  test "treats Deezer's zero and placeholder values as unknown" do
    attrs = SongEnrichment.attributes_from_track(
      "bpm" => 0, "release_date" => "0000-00-00", "rank" => 0
    )

    assert_empty attrs
  end

  test "handles missing keys" do
    assert_empty SongEnrichment.attributes_from_track({})
  end

  test "genre_for returns nil for a blank album id without calling Deezer" do
    Deezer::Client.stub(:album_details, ->(*) { raise "must not be called" }) do
      assert_nil SongEnrichment.genre_for(nil)
      assert_nil SongEnrichment.genre_for("")
    end
  end

  test "genre_for rejects Deezer's catch-all genre" do
    Deezer::Client.stub(:album_details, { "genres" => { "data" => [ { "name" => "All" } ] } }) do
      assert_nil SongEnrichment.genre_for(42)
    end
  end

  test "genre_for returns the album genre" do
    Deezer::Client.stub(:album_details, { "genres" => { "data" => [ { "name" => "Rock" } ] } }) do
      assert_equal "Rock", SongEnrichment.genre_for(42)
    end
  end

  test "enrich! marks the song enriched even when Deezer fails" do
    song = songs(:unenriched)

    Deezer::Client.stub(:track_details, ->(*) { raise Deezer::Client::Error, "down" }) do
      SongEnrichment.enrich!(song)
    end

    assert song.reload.enriched_at.present?
    assert_nil song.genre
  end
end
