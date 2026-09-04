require "test_helper"
require "open3"

# Pins the contract between ComputeSession::Remote and script/gpu_agent.py.
# The two halves are in different languages and normally only ever meet over
# an SSH connection to a machine that is not in CI, so nothing else would
# notice one of them drifting. Here the agent is run directly, standing in for
# "ssh <box> python gpu_agent.py".
class GpuAgentTest < ActiveSupport::TestCase
  AGENT = Rails.root.join("script/gpu_agent.py")

  def setup
    @work_root = Rails.root.join("tmp/gpu-agent-test-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@work_root)
    @token = SecureRandom.hex(ComputeSession::Remote::TOKEN_BYTES)
    skip "no python available to run the agent" unless python
  end

  def teardown
    FileUtils.rm_rf(@work_root)
  end

  def python
    @python ||= [ Rails.root.join("vendor/karaoke/bin/python").to_s, "/usr/bin/python3" ]
      .find { |candidate| File.executable?(candidate) } || `which python3`.strip.presence
  end

  # Mirrors what GpuHost does: one request on stdin, one response, and the exit
  # status is what says whether it worked. `body` is the raw payload an upload
  # sends after the header.
  def agent(payload, body = nil)
    output = nil
    status = Open3.popen2({ "KARAOKE_GPU_WORKDIR" => @work_root.to_s }, python, AGENT.to_s) do |stdin, stdout, thread|
      stdin.binmode
      stdin.write("#{JSON.generate(payload)}\n")
      stdin.write(body) if body
      stdin.close
      stdout.binmode
      output = stdout.read
      thread.value
    end

    [ status, output ]
  end

  def json(payload, body = nil)
    status, output = agent(payload, body)
    [ status.success?, (JSON.parse(output.lines.first.to_s) rescue nil) ]
  end

  test "ping answers without importing anything expensive" do
    ok, response = json(action: "ping")

    assert ok
    assert response["ok"]
    assert response["platform"].present?
  end

  test "exec substitutes the work placeholder and reports declared outputs" do
    ok, response = json(
      action: "exec", token: @token,
      argv: [ "/bin/sh", "-c", "printf hello > #{ComputeSession::WORK}/greeting.txt" ],
      outputs: [ "greeting.txt" ], timeout: 30
    )

    assert ok
    assert response["ok"]
    assert_equal 5, response.dig("outputs", "greeting.txt")
    assert_equal @token, response["token"]
  end

  test "a second exec on the same token shares the directory" do
    json(
      action: "exec", token: @token,
      argv: [ "/bin/sh", "-c", "printf hi > #{ComputeSession::WORK}/first.txt" ],
      outputs: [ "first.txt" ], timeout: 30
    )

    _ok, response = json(
      action: "exec", token: @token,
      argv: [ "/bin/sh", "-c", "cat #{ComputeSession::WORK}/first.txt > #{ComputeSession::WORK}/second.txt" ],
      outputs: [ "second.txt" ], timeout: 30
    )

    assert_equal 2, response.dig("outputs", "second.txt"),
      "the download, the separation and the encode all have to land in one directory"
  end

  test "a non-zero exit is reported alongside whatever it did produce" do
    _ok, response = json(
      action: "exec", token: @token,
      argv: [ "/bin/sh", "-c", "printf partial > #{ComputeSession::WORK}/out.mp3; echo 403 >&2; exit 1" ],
      outputs: [ "out.mp3" ], timeout: 30
    )

    assert_not response["ok"]
    assert_equal 1, response["status"]
    assert_includes response["stderr"], "403"
    # yt-dlp exits non-zero when --max-downloads stops it, having produced
    # exactly the file that was wanted -- so the file has to be reported too.
    assert_equal 7, response.dig("outputs", "out.mp3")
  end

  test "a command that overruns its timeout is killed and says so" do
    _ok, response = json(action: "exec", token: @token, argv: [ "/bin/sh", "-c", "sleep 30" ], timeout: 1)

    assert_not response["ok"]
    assert response["timed_out"]
  end

  test "a missing binary is named rather than reported as a plain failure" do
    _ok, response = json(action: "exec", token: @token, argv: [ "/nonexistent/yt-dlp" ], timeout: 30)

    assert_not response["ok"]
    assert_includes response["error"], "yt-dlp"
  end

  test "put stores exactly the bytes that followed the header" do
    payload = "lyrics\x00\xffbinary".b

    ok, response = json({ action: "put", token: @token, name: "lyrics.lrc", size: payload.bytesize }, payload)

    assert ok
    assert_equal payload.bytesize, response["size"]
    assert_equal payload, File.binread(@work_root.join(@token, "lyrics.lrc"))
  end

  test "fetch returns raw bytes, unmangled" do
    payload = (0..255).map(&:chr).join.b
    json({ action: "put", token: @token, name: "audio.mp3", size: payload.bytesize }, payload)

    status, output = agent(action: "fetch", token: @token, name: "audio.mp3")

    assert status.success?
    assert_equal payload, output.b, "a newline translation here would corrupt every mp3"
  end

  test "fetching something that was never staged fails rather than returning nothing" do
    status, output = agent(action: "fetch", token: @token, name: "absent.mp3")

    assert_not status.success?, "a truncated artifact must not look like a finished one"
    assert_empty output
  end

  test "a filename cannot escape the work directory" do
    [ "../escaped.mp3", "..", "/etc/passwd", "sub/dir.mp3", ".hidden" ].each do |name|
      status, = agent(action: "put", token: @token, name: name, size: 1)

      assert_not status.success?, "#{name.inspect} was accepted as a staged name"
    end
  end

  test "a malformed token is refused" do
    [ "../../etc", "short", "#{SecureRandom.hex(16)}/x", "" ].each do |token|
      status, = agent(action: "fetch", token: token, name: "audio.mp3")

      assert_not status.success?, "#{token.inspect} was accepted as a work token"
    end
  end

  test "release drops the directory" do
    json({ action: "put", token: @token, name: "audio.mp3", size: 2 }, "hi")
    assert File.directory?(@work_root.join(@token))

    ok, = json(action: "release", token: @token)

    assert ok
    assert_not File.exist?(@work_root.join(@token))
  end

  test "an unreadable request is refused rather than guessed at" do
    status = Open3.popen2({ "KARAOKE_GPU_WORKDIR" => @work_root.to_s }, python, AGENT.to_s) do |stdin, stdout, thread|
      stdin.write("this is not json\n")
      stdin.close
      stdout.read
      thread.value
    end
    assert_not status.success?

    ok, = json(action: "explode")
    assert_not ok
  end
end
