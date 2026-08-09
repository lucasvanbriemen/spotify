require "test_helper"
require "open3"

# Drives script/karaoke_separate.py's --reanalyze mode over a hand-built pitch
# curve (test/fixtures/files/karaoke/pitch.json — three sung notes, one split
# by a consonant-sized gap, plus a blip too short to count). Testing through
# the CLI keeps the exact contract VocalSeparation invokes under test, without
# adding a Python test framework.
#
# Skipped where the analysis venv isn't installed, so CI and a bare checkout
# stay green — the script also carries `--self-test` for the same assertions.
class KaraokeReanalysisTest < ActiveSupport::TestCase
  PYTHON = VocalSeparation.send(:python_executable)
  SCRIPT = Rails.root.join("script/karaoke_separate.py")
  FIXTURES = Rails.root.join("test/fixtures/files/karaoke")

  setup do
    skip "vendor/karaoke venv not installed" unless PYTHON.exist?
    @dir = Pathname.new(Dir.mktmpdir("karaoke-reanalysis"))
  end

  teardown do
    FileUtils.remove_entry(@dir) if @dir&.directory?
  end

  def reanalyze(*extra)
    command = [ PYTHON.to_s, SCRIPT.to_s, "--reanalyze", FIXTURES.join("pitch.json").to_s, *extra ]
    _out, err, status = Open3.capture3(*command)
    [ status.success?, err ]
  end

  def notes_out = @dir.join("notes.json")
  def words_out = @dir.join("words.json")

  test "the melody quantizes to the notes that were sung" do
    success, err = reanalyze("--notes-out", notes_out.to_s)
    assert success, err

    payload = JSON.parse(notes_out.read)
    notes = payload["notes"]

    # Vibrato stays inside a note, the 100ms gap merges, the 50ms blip is gone.
    assert_equal [ 60, 64, 67 ], notes.map { |note| note["midi"] }
    assert_equal 60, payload["midi_min"]
    assert_equal 67, payload["midi_max"]
    assert_in_delta 0.5, notes.first["start"], 0.001
    assert_in_delta 1.1, notes[1]["end"] - notes[1]["start"], 0.001
  end

  test "notes never overlap and always move forward" do
    reanalyze("--notes-out", notes_out.to_s)
    notes = JSON.parse(notes_out.read)["notes"]

    notes.each { |note| assert_operator note["end"], :>, note["start"] }
    notes.each_cons(2) { |previous, following| assert_operator following["start"], :>=, previous["end"] }
  end

  test "the highest sustained note is golden" do
    reanalyze("--notes-out", notes_out.to_s)
    notes = JSON.parse(notes_out.read)["notes"]

    assert_equal 1, notes.count { |note| note["golden"] }
    assert_equal 67, notes.find { |note| note["golden"] }["midi"]
  end

  test "words land inside their line and on sung audio" do
    success, err = reanalyze("--notes-out", notes_out.to_s, "--words-out", words_out.to_s, "--lrc", FIXTURES.join("lyrics.lrc").to_s)
    assert success, err

    lines = JSON.parse(words_out.read)["lines"]

    assert_equal 3, lines.size
    assert_equal %w[one two three], lines.first["words"].map { |word| word["w"] }
    # The line ends when the singing does, not when the next line starts.
    assert_in_delta 1.5, lines.first["end"], 0.001

    lines.each do |line|
      line["words"].each do |word|
        assert_operator word["start"], :>=, line["start"] - 0.001
        assert_operator word["end"], :<=, line["end"] + 0.001
        assert_operator word["end"], :>=, word["start"]
      end
    end
  end

  test "enhanced LRC word tags are used verbatim" do
    success, err = reanalyze("--words-out", words_out.to_s, "--lrc", FIXTURES.join("enhanced.lrc").to_s)
    assert success, err

    first = JSON.parse(words_out.read)["lines"].first

    assert_equal %w[one two three], first["words"].map { |word| word["w"] }
    assert_in_delta 0.5, first["words"][0]["start"], 0.001
    assert_in_delta 1.0, first["words"][1]["start"], 0.001
    assert_in_delta 1.2, first["words"][2]["start"], 0.001
  end

  test "word timings are skipped, not failed, when there are no lyrics" do
    success, err = reanalyze("--notes-out", notes_out.to_s, "--words-out", words_out.to_s)

    assert success, err
    assert_not words_out.exist?
    assert notes_out.exist?
  end

  test "the built-in self test passes" do
    _out, err, status = Open3.capture3(PYTHON.to_s, SCRIPT.to_s, "--self-test")

    assert status.success?, err
  end
end
