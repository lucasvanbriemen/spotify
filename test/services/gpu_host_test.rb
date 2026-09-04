require "test_helper"
require "minitest/mock"

class GpuHostTest < ActiveSupport::TestCase
  def setup
    @original = ENV.to_h.slice(*%w[
      KARAOKE_GPU_SSH KARAOKE_GPU_ROOT KARAOKE_GPU_PYTHON
      KARAOKE_GPU_AGENT KARAOKE_GPU_DEVICE KARAOKE_GPU_EXE_SUFFIX
    ])
    GpuHost.forget_availability!
  end

  def teardown
    %w[KARAOKE_GPU_SSH KARAOKE_GPU_ROOT KARAOKE_GPU_PYTHON
       KARAOKE_GPU_AGENT KARAOKE_GPU_DEVICE KARAOKE_GPU_EXE_SUFFIX].each { |key| ENV.delete(key) }
    ENV.update(@original)
    GpuHost.forget_availability!
  end

  test "is unconfigured, and so unavailable, without a target" do
    ENV.delete("KARAOKE_GPU_SSH")

    assert_not GpuHost.configured?
    assert_not GpuHost.available?
  end

  test "derives every remote path from the checkout, Windows-style by default" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/Users/karaoke/music"

    assert GpuHost.configured?
    assert_equal "C:/Users/karaoke/music/vendor/karaoke/Scripts/python.exe", GpuHost.python
    assert_equal "C:/Users/karaoke/music/script/gpu_agent.py", GpuHost.agent
    assert_equal "C:/Users/karaoke/music/script/karaoke_separate.py", GpuHost.script("karaoke_separate.py")
    assert_equal "C:/Users/karaoke/music/bin/yt-dlp.exe", GpuHost.tool("yt-dlp")
    assert_equal "C:/Users/karaoke/music/bin", GpuHost.bin_dir
  end

  test "an empty executable suffix moves the whole layout to a unix host" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "/srv/music"
    ENV["KARAOKE_GPU_EXE_SUFFIX"] = ""

    assert_equal "/srv/music/vendor/karaoke/bin/python", GpuHost.python
    assert_equal "/srv/music/bin/ffmpeg", GpuHost.tool("ffmpeg")
  end

  test "an explicit python overrides the derived one" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/music"
    ENV["KARAOKE_GPU_PYTHON"] = "D:/venvs/karaoke/Scripts/python.exe"

    assert_equal "D:/venvs/karaoke/Scripts/python.exe", GpuHost.python
  end

  test "a trailing slash on the checkout does not double up in derived paths" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/music/"

    assert_equal "C:/music/script/gpu_agent.py", GpuHost.agent
  end

  test "a configured target with no checkout cannot be used" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV.delete("KARAOKE_GPU_ROOT")

    assert GpuHost.configured?
    assert_not GpuHost.available?, "nothing can be run without knowing where the agent is"
  end

  test "the ssh timeout outlasts the command it is waiting on" do
    assert_operator GpuHost.ssh_timeout_for(1800), :>, 1800
  end

  test "availability is asked once and then cached" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/music"
    calls = 0

    GpuHost.stub(:call, ->(*, **) { calls += 1; { "ok" => true } }) do
      assert GpuHost.available?
      assert GpuHost.available?
      assert GpuHost.available?
    end

    assert_equal 1, calls, "a queue of songs must not each re-ping the box"
  end

  test "an unreachable box is retried, then remembered as unreachable" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/music"
    calls = 0

    GpuHost.stub(:call, ->(*, **) { calls += 1; nil }) do
      GpuHost.stub(:sleep, ->(_) { }) do
        assert_not GpuHost.available?
        assert_not GpuHost.available?
      end
    end

    assert_equal GpuHost::PING_BACKOFF_SECONDS.size, calls,
      "the desktop gets a few attempts in case it is waking up, but only for the first caller"
  end

  test "a box that answers on a later attempt is still used" do
    ENV["KARAOKE_GPU_SSH"] = "karaoke@10.0.0.2"
    ENV["KARAOKE_GPU_ROOT"] = "C:/music"
    answers = [ nil, { "ok" => true } ]

    GpuHost.stub(:call, ->(*, **) { answers.shift }) do
      GpuHost.stub(:sleep, ->(_) { }) do
        assert GpuHost.available?
      end
    end
  end
end
