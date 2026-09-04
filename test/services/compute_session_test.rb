require "test_helper"
require "minitest/mock"

class ComputeSessionTest < ActiveSupport::TestCase
  def setup
    @scratch = Rails.root.join("tmp/compute-session-test")
    FileUtils.mkdir_p(@scratch)
  end

  def teardown
    FileUtils.rm_rf(@scratch)
  end

  # --- choosing a host -------------------------------------------------------

  test "runs here when the GPU box does not answer" do
    GpuHost.stub(:available?, false) do
      ComputeSession.open("t") do |session|
        assert_not session.remote?
        assert_kind_of ComputeSession::Local, session
      end
    end
  end

  test "runs on the GPU box when it answers" do
    GpuHost.stub(:available?, true) do
      ComputeSession.open("t") do |session|
        assert session.remote?
      end
    end
  end

  test "prefer_gpu false stays here even when the box answers" do
    GpuHost.stub(:available?, true) do
      ComputeSession.open("t", prefer_gpu: false) do |session|
        assert_not session.remote?
      end
    end
  end

  test "the scratch directory is cleaned up even when the work raises" do
    leaked = nil

    assert_raises(RuntimeError) do
      GpuHost.stub(:available?, false) do
        ComputeSession.open("t") do |session|
          session.run("/bin/sh", "-c", "printf x > #{session.path('a.txt')}",
                      outputs: [ "a.txt" ], timeout_seconds: 10)
          leaked = session.send(:resolve, session.path("a.txt"))
          raise "separation blew up"
        end
      end
    end

    assert_not File.exist?(leaked), "a failed prepare must not leave its wavs behind"
  end

  test "open hands back what the block returned" do
    GpuHost.stub(:available?, false) do
      assert_equal :done, ComputeSession.open("t") { :done }
    end
  end

  # --- the local back end ----------------------------------------------------

  def local
    session = ComputeSession::Local.new
    yield session
  ensure
    session&.release
  end

  test "the work placeholder is replaced wherever it appears in an argument" do
    local do |session|
      result = session.run(
        "/bin/sh", "-c", "printf hello > #{session.path('greeting.txt')}",
        outputs: [ "greeting.txt" ], timeout_seconds: 10
      )

      assert result.ok?
      assert result.produced?("greeting.txt")
      assert_equal 5, result.outputs["greeting.txt"]
    end
  end

  test "an output that never appeared is not reported as produced" do
    local do |session|
      result = session.run("/bin/sh", "-c", "true", outputs: [ "missing.mp3" ], timeout_seconds: 10)

      assert result.ok?
      assert_not result.produced?("missing.mp3")
    end
  end

  test "a command that fails is reported as failed, with its stderr" do
    local do |session|
      result = session.run("/bin/sh", "-c", "echo 'HTTP Error 403' >&2; exit 1", timeout_seconds: 10)

      assert_not result.ok?
      assert_not result.timed_out?
      assert_includes result.stderr, "403"
    end
  end

  test "a command that overruns its timeout is killed and reported" do
    local do |session|
      result = session.run("/bin/sh", "-c", "sleep 30", timeout_seconds: 1)

      assert_not result.ok?
      assert result.timed_out?
    end
  end

  test "stdout comes back, and its last line is what a measurement is read from" do
    local do |session|
      result = session.run("/bin/sh", "-c", "echo noise; echo 0.125", timeout_seconds: 10)

      assert_equal "0.125", result.last_line
    end
  end

  test "an enormous stdout is truncated rather than held whole" do
    local do |session|
      result = session.run("/bin/sh", "-c", "yes progress | head -200000", timeout_seconds: 60)

      assert_operator result.stdout.bytesize, :<=, ComputeSession::OUTPUT_TAIL_BYTES,
        "a demucs progress bar must not be carried around in memory"
    end
  end

  test "put stages a file the command can then read" do
    source = @scratch.join("input.txt")
    source.write("lyrics")

    local do |session|
      assert session.put(source, "lyrics.lrc")
      result = session.run(
        "/bin/sh", "-c", "cat #{session.path('lyrics.lrc')} > #{session.path('echoed.txt')}",
        outputs: [ "echoed.txt" ], timeout_seconds: 10
      )

      assert_equal 6, result.outputs["echoed.txt"]
    end
  end

  test "put reports a missing source rather than staging nothing quietly" do
    local do |session|
      assert_not session.put(@scratch.join("absent.mp3"), "original.mp3")
      assert_not session.put(nil, "original.mp3")
    end
  end

  test "fetch brings a result out to its final path" do
    destination = @scratch.join("nested/instrumental.mp3")

    local do |session|
      session.run("/bin/sh", "-c", "printf audio > #{session.path('instrumental.mp3')}",
                  outputs: [ "instrumental.mp3" ], timeout_seconds: 10)

      assert session.fetch("instrumental.mp3", destination)
      assert_equal "audio", destination.read
    end
  end

  test "fetch leaves nothing behind when there is nothing to fetch" do
    destination = @scratch.join("instrumental.mp3")

    local do |session|
      assert_not session.fetch("never-made.mp3", destination)
      assert_not destination.exist?
      assert_empty Dir.glob("#{@scratch}/*.part"), "a failed fetch must not leave a partial artifact"
    end
  end

  test "the temp directory a command scatters intermediates through is its own" do
    local do |session|
      result = session.run("/bin/sh", "-c", "printf %s \"$TMPDIR\" > #{session.path('tmp.txt')}",
                           outputs: [ "tmp.txt" ], timeout_seconds: 10)

      assert result.produced?("tmp.txt")
      assert_equal session.send(:resolve, ComputeSession::WORK),
        File.read(session.send(:resolve, session.path("tmp.txt")))
    end
  end

  test "release removes the scratch directory" do
    session = ComputeSession::Local.new
    directory = session.send(:resolve, ComputeSession::WORK)

    assert File.directory?(directory)
    session.release
    assert_not File.exist?(directory)
  end
end
