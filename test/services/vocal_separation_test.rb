require "test_helper"

# Readiness is "whatever's on disk", so these tests write the artifact files
# themselves rather than running demucs. Each uses its own ISRC so they stay
# safe under the parallel test runner.
class VocalSeparationTest < ActiveSupport::TestCase
  setup do
    @isrc = "TEST#{SecureRandom.hex(6).upcase}"
    FileUtils.mkdir_p(VocalSeparation::AUDIO_DIR)
  end

  teardown do
    Dir.glob(VocalSeparation::AUDIO_DIR.join("#{@isrc}*")).each { |path| FileUtils.rm_f(path) }
  end

  def write_required_artifacts
    VocalSeparation.instrumental_path(@isrc).write("mp3")
    VocalSeparation.pitch_path(@isrc).write('{"hop_seconds":0.025,"hz":[]}')
    VocalSeparation.notes_path(@isrc).write('{"notes":[],"midi_min":null,"midi_max":null}')
  end

  def write_manifest(payload)
    VocalSeparation.manifest_path(@isrc).write(payload.is_a?(String) ? payload : JSON.generate(payload))
  end

  def valid_manifest(artifacts: {}, difficulty: nil)
    {
      "version" => VocalSeparation::ARTIFACT_VERSION,
      "created_at" => Time.current.utc.iso8601,
      "instrumental_source" => "demucs",
      "artifacts" => { "instrumental" => true, "pitch" => true, "notes" => true, "vocals" => true, "words" => false }.merge(artifacts),
      "difficulty" => difficulty
    }
  end

  test "artifacts alone are not ready without a manifest" do
    write_required_artifacts

    assert_not VocalSeparation.ready?(@isrc)
  end

  test "a manifest from an older artifact version is not ready" do
    write_required_artifacts
    write_manifest(valid_manifest.merge("version" => VocalSeparation::ARTIFACT_VERSION - 1))

    assert_not VocalSeparation.ready?(@isrc)
  end

  test "a current manifest with every required artifact is ready" do
    write_required_artifacts
    write_manifest(valid_manifest)

    assert VocalSeparation.ready?(@isrc)
  end

  test "a current manifest is not enough when a required artifact is missing" do
    write_required_artifacts
    write_manifest(valid_manifest)
    FileUtils.rm_f(VocalSeparation.notes_path(@isrc))

    assert_not VocalSeparation.ready?(@isrc)
  end

  test "a malformed manifest reads as not ready rather than raising" do
    write_required_artifacts
    write_manifest("{not json")

    assert_not VocalSeparation.ready?(@isrc)
  end

  test "optional artifacts and difficulty are readable from the manifest" do
    difficulty = { "level" => "medium", "range_semitones" => 15, "notes_per_second" => 2.0, "longest_note_seconds" => 1.2 }
    write_required_artifacts
    write_manifest(valid_manifest(artifacts: { "vocals" => false }, difficulty: difficulty))

    assert_equal false, VocalSeparation.artifacts(@isrc)["vocals"]
    assert_equal true, VocalSeparation.artifacts(@isrc)["notes"]
    assert_equal "medium", VocalSeparation.difficulty(@isrc)["level"]
  end

  test "an unknown song has no artifacts and no difficulty" do
    assert_empty VocalSeparation.artifacts(@isrc)
    assert_nil VocalSeparation.difficulty(@isrc)
    assert_not VocalSeparation.ready?(@isrc)
  end

  test "the legacy upgrade declines when there is no pitch curve to reanalyze" do
    VocalSeparation.instrumental_path(@isrc).write("mp3")

    assert_not VocalSeparation.send(:upgrade_legacy, @isrc)
  end

  test "the manifest records which artifacts were actually produced" do
    write_required_artifacts
    VocalSeparation.vocals_path(@isrc).write("mp3")

    VocalSeparation.send(:write_manifest, @isrc, instrumental_source: "youtube")

    assert VocalSeparation.ready?(@isrc)
    assert_equal "youtube", JSON.parse(VocalSeparation.manifest_path(@isrc).read)["instrumental_source"]
    assert_equal true, VocalSeparation.artifacts(@isrc)["vocals"]
    assert_equal false, VocalSeparation.artifacts(@isrc)["words"]
    # An empty note list is legal (rap, spoken word) and carries no difficulty.
    assert_nil VocalSeparation.difficulty(@isrc)
  end
end
