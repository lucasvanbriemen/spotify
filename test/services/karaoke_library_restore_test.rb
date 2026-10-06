require "test_helper"
require "minitest/mock"

class KaraokeLibraryRestoreTest < ActiveSupport::TestCase
  ISRC = "RESTORE00001".freeze
  VIDEO_ID = "a_b-c1234XY".freeze
  DETAILS = {
    "title" => "Restored Song", "duration" => 200,
    "artist" => { "name" => "Tester" },
    "album" => { "title" => "Album", "cover_medium" => "https://example.com/art.jpg", "id" => nil }
  }.freeze

  setup do
    # What the all-in-one rekey leaves behind: the YouTube-keyed row with the
    # old row's title and artist, and the scores moved under it.
    @twin = Song.create!(id: VIDEO_ID, title: "Restored Song", artist: "Tester", album: "Album",
                         duration: 199, image_url: Song::PLACEHOLDER_IMAGE)
    @score = KaraokeScore.create!(song: @twin, singer_name: "Lucas", score: 7000)
    @log = []
  end

  teardown do
    Song.where(id: [ ISRC, VIDEO_ID ]).destroy_all
  end

  test "recreates the ISRC row and moves the scores back to it" do
    result = run_restore(prepared: [ ISRC ], deezer: { ISRC => DETAILS })

    assert_equal 1, result.restored
    assert_equal 1, result.scores_moved
    assert_equal "Restored Song", Song.find(ISRC).title
    assert_equal ISRC, @score.reload.song_id
    assert Song.exists?(VIDEO_ID), "the other app's row is left alone"
  end

  test "is a no-op for a track that already has its row" do
    Song.create!(id: ISRC, title: "Restored Song", artist: "Tester", album: "Album", duration: 200, image_url: Song::PLACEHOLDER_IMAGE)

    result = run_restore(prepared: [ ISRC ], deezer: {})
    assert_equal 0, result.restored
    assert_equal VIDEO_ID, @score.reload.song_id
  end

  test "leaves scores where they are when the match is ambiguous" do
    Song.create!(id: "zzzzzzzzzzz", title: "Restored Song", artist: "Tester", album: "Album", duration: 201, image_url: Song::PLACEHOLDER_IMAGE)

    result = run_restore(prepared: [ ISRC ], deezer: { ISRC => DETAILS })
    assert_equal 1, result.restored
    assert_equal 0, result.scores_moved
    assert_equal VIDEO_ID, @score.reload.song_id
  ensure
    Song.where(id: "zzzzzzzzzzz").destroy_all
  end

  test "reports an ISRC Deezer no longer knows instead of failing" do
    result = run_restore(prepared: [ ISRC ], deezer: { ISRC => { "error" => { "code" => 800 } } })
    assert_equal [ ISRC ], result.missing
    assert_not Song.exists?(ISRC)
  end

  private

  def run_restore(prepared:, deezer:)
    restore = KaraokeLibraryRestore.new(logger: ->(line) { @log << line })
    restore.stub(:sleep, nil) do
      VocalSeparation.stub(:prepared_isrcs, prepared) do
        Deezer::Client.stub(:track_details, ->(isrc) { deezer.fetch(isrc) }) do
          SongEnrichment.stub(:genre_for, nil) do
            restore.run(only_prepared: true)
          end
        end
      end
    end
  end
end
