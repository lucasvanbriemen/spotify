# ComputeSession on the GPU box: the same work directory, on the far side of an
# SSH connection, driven through script/gpu_agent.py.
#
# The token is minted here rather than by the agent so that the directory has a
# name before anything is put in it -- which is what lets the separation and
# the YouTube instrumental download, which run concurrently for one song, share
# a directory without either waiting to be told where it is. It is also the
# reason a prepare costs so little network: the original mp3 is downloaded on
# that box and stays there, and only the finished artifacts come back.
class ComputeSession::Remote < ComputeSession
  # Matches the agent's TOKEN_PATTERN, which rejects anything else outright.
  TOKEN_BYTES = 16
  RELEASE_TIMEOUT_SECONDS = 30
  # A put is one SSH round trip carrying a whole file; a vocal stem over a
  # ZeroTier link is seconds, but a link that has gone away should not hold a
  # queue for minutes.
  PUT_TIMEOUT_SECONDS = 300
  FETCH_TIMEOUT_SECONDS = 600

  def initialize
    @token = SecureRandom.hex(TOKEN_BYTES)
  end

  def remote? = true
  def where = "gpu #{GpuHost.target}"

  def python = GpuHost.python
  def tool(name) = GpuHost.tool(name)
  def script(name) = GpuHost.script(name)
  def bin_dir = GpuHost.bin_dir
  def device = GpuHost.device

  def put(local_path, name)
    return false unless local_path && File.file?(local_path.to_s)

    size = File.size(local_path.to_s)
    response = File.open(local_path.to_s, "rb") do |file|
      GpuHost.call(
        { action: "put", token: @token, name: name, size: size },
        body: file, timeout_seconds: PUT_TIMEOUT_SECONDS
      )
    end

    return true if response&.dig("ok")

    Rails.logger.warn("[gpu] staging #{name} (#{size} bytes) failed")
    false
  end

  def run(*argv, outputs: [], timeout_seconds:, env: {})
    response = GpuHost.call(
      {
        action: "exec", token: @token, argv: argv.map(&:to_s), outputs: outputs.map(&:to_s),
        env: env.transform_keys(&:to_s).transform_values(&:to_s), timeout: timeout_seconds
      },
      timeout_seconds: GpuHost.ssh_timeout_for(timeout_seconds)
    )

    # No response at all means the connection died or ssh was killed for
    # outliving even the padded timeout. Reported as a failed command, which
    # is what makes the caller fall back to this host.
    unless response
      Rails.logger.warn("[gpu] #{argv.first} produced no response from #{GpuHost.target}")
      return Result.new(ok: false, timed_out: true)
    end

    log_failure(argv, response) unless response["ok"]

    Result.new(
      ok: response["ok"], timed_out: response["timed_out"], seconds: response["seconds"],
      stdout: response["stdout"].to_s, stderr: response["stderr"].to_s,
      outputs: response["outputs"] || {}
    )
  end

  def fetch(name, destination)
    return true if GpuHost.stream_to(
      { action: "fetch", token: @token, name: name }, destination.to_s,
      timeout_seconds: FETCH_TIMEOUT_SECONDS
    )

    Rails.logger.warn("[gpu] fetching #{name} for #{destination} failed")
    false
  end

  # Best-effort: the agent sweeps directories older than twelve hours anyway,
  # so a release lost to a link that dropped costs disk space for an afternoon
  # rather than leaking it.
  def release
    GpuHost.call({ action: "release", token: @token }, timeout_seconds: RELEASE_TIMEOUT_SECONDS)
  end

  private

  def log_failure(argv, response)
    reason = if response["timed_out"] then "timed out"
    elsif response["error"] then response["error"]
    else "exit #{response['status']}"
    end
    Rails.logger.warn("[gpu] #{File.basename(argv.first.to_s)} #{reason}: #{response['stderr'].to_s.lines.last(3).join.strip}")
  end
end
