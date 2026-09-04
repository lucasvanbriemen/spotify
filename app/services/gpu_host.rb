# The SSH end of karaoke's GPU offload: prod talks to a machine that has a
# graphics card, and this is the only thing that knows how.
#
# Why it exists: htdemucs is ~80% of a prepare and prod has no GPU, so a
# separation takes ~205s there against ~38s on a consumer GPU. The same song
# also downloads better from a home connection than from a datacenter one --
# the whole YtDlp player-client walk exists because YouTube 403s this server --
# so the download moves across with it.
#
# Every request is one SSH invocation of a fixed command:
#
#     ssh <target> <python> <agent.py>
#
# with the variable part -- argv, filenames, sizes -- travelling as JSON on
# stdin. Nothing is ever interpolated into a remote shell command. That is a
# hard requirement rather than a nicety: the GPU box runs Win32-OpenSSH, so a
# remote command string is parsed by cmd.exe, whose quoting agrees with neither
# Ruby's nor sh's, and a song title is quite enough to break it.
#
# Configuration is all environment, read per call, so the box can be moved or
# switched off without a deploy:
#
#   KARAOKE_GPU_SSH      karaoke@10.167.192.19 -- absent means "no offload",
#                        and every caller silently keeps working locally
#   KARAOKE_GPU_ROOT     the checkout on that box, e.g. C:/Users/karaoke/music
#   KARAOKE_GPU_EXE_SUFFIX  ".exe" by default, since the box is Windows; set it
#                        empty for a Linux GPU host and every path below follows
#   KARAOKE_GPU_PYTHON   its venv interpreter   (default: <root>/vendor/karaoke/Scripts/python.exe)
#   KARAOKE_GPU_AGENT    this repo's gpu_agent.py on that box (default: <root>/script/gpu_agent.py)
#   KARAOKE_GPU_DEVICE   torch device for demucs (default: cuda)
#   KARAOKE_GPU_SSH_KEY  identity file, when the default keys are not the ones
module GpuHost
  DEFAULT_DEVICE = "cuda".freeze
  # The GPU box is a Windows desktop, where bin/ holds yt-dlp.exe and ffmpeg.exe
  # (exactly what ExecutablePath already reaches for on a Windows host) and a
  # venv puts its interpreter in Scripts/ rather than bin/. One knob rather
  # than a path per tool, so pointing this at a Linux box is a single change.
  DEFAULT_EXE_SUFFIX = ".exe".freeze
  WINDOWS_PYTHON_SUFFIX = "vendor/karaoke/Scripts/python.exe".freeze
  UNIX_PYTHON_SUFFIX = "vendor/karaoke/bin/python".freeze
  DEFAULT_AGENT_SUFFIX = "script/gpu_agent.py".freeze

  # A liveness check imports nothing on the far side, so the only cost is the
  # round trip and the SSH handshake.
  PING_TIMEOUT_SECONDS = 10
  PROBE_TIMEOUT_SECONDS = 120
  # The box is somebody's desktop: it sleeps, it reboots, it comes back. Three
  # attempts spread over ~7s covers that without making a genuinely-off machine
  # cost every job in the queue -- which is what the caches below are for.
  PING_BACKOFF_SECONDS = [ 0, 2, 5 ].freeze
  REACHABLE_TTL_SECONDS = 60
  # Longer than the reachable one: once it is established that the desktop is
  # off, a queue of ten songs should not each pay the retries to rediscover it.
  UNREACHABLE_TTL_SECONDS = 120

  # 64KB is the usual pipe buffer; anything at or under it can be written
  # before the child is waited on without risking a deadlock.
  STREAM_CHUNK_BYTES = 64 * 1024

  @availability = nil
  @availability_lock = Mutex.new

  class << self
    def configured?
      target.present?
    end

    def target
      ENV["KARAOKE_GPU_SSH"].presence
    end

    def device
      ENV.fetch("KARAOKE_GPU_DEVICE", DEFAULT_DEVICE).presence
    end

    # The checkout on the far side. Paths are joined with "/" rather than
    # File.join: this process may be on Windows too, and the remote separator
    # has nothing to do with the local one. Forward slashes are what
    # Win32-OpenSSH and Python both accept.
    def root
      ENV["KARAOKE_GPU_ROOT"].presence&.delete_suffix("/")
    end

    def exe_suffix
      ENV.fetch("KARAOKE_GPU_EXE_SUFFIX", DEFAULT_EXE_SUFFIX)
    end

    def python
      return ENV["KARAOKE_GPU_PYTHON"] if ENV["KARAOKE_GPU_PYTHON"].present?

      remote_join(exe_suffix == ".exe" ? WINDOWS_PYTHON_SUFFIX : UNIX_PYTHON_SUFFIX)
    end

    # bin/yt-dlp and bin/ffmpeg are installed per host and deliberately not
    # tracked (see .gitignore), so this is where they are, not proof they are.
    # A missing one comes back from the agent as "not executable on this host".
    def tool(name)
      remote_join("bin", "#{name}#{exe_suffix}")
    end

    def script(name)
      remote_join("script", name)
    end

    def bin_dir
      remote_join("bin")
    end

    def agent
      ENV["KARAOKE_GPU_AGENT"].presence || remote_join(DEFAULT_AGENT_SUFFIX)
    end

    # Every response's timeout has to outlast the command the agent is running,
    # or ssh gets killed here first and a separation that actually finished is
    # read as a failure -- and worse, retried.
    def ssh_timeout_for(command_timeout)
      command_timeout + 60
    end

    def remote_join(*parts)
      [ root, *parts ].compact.join("/").presence
    end

    # A space in either of these breaks the remote command string, and the
    # failure is silent and total: cmd.exe reads the first word as the program
    # and the rest as arguments to it. Reported by karaoke:gpu:probe rather
    # than raised, since it is a setup mistake, not a runtime condition.
    def unquotable_paths
      { "KARAOKE_GPU_PYTHON" => python, "KARAOKE_GPU_AGENT" => agent }
        .select { |_, path| path.to_s.match?(/[\s"]/) }
    end

    # Whether work should be sent there at all. Cached both ways, and retried
    # before giving up, because the answer decides between ~40s and ~205s and
    # is wrong in both directions if asked only once.
    # Enough configuration to actually run something: a target, and somewhere
    # on it to find the interpreter and the agent. Checked at the point of use
    # as well as before it, so a half-configured host is a no-op rather than a
    # TypeError out of Process.spawn.
    def usable?
      target.present? && python.present? && agent.present?
    end

    def available?
      return false unless usable?

      @availability_lock.synchronize do
        cached = @availability
        return cached[:reachable] if cached && Process.clock_gettime(Process::CLOCK_MONOTONIC) < cached[:until]

        reachable = ping_with_retries
        ttl = reachable ? REACHABLE_TTL_SECONDS : UNREACHABLE_TTL_SECONDS
        @availability = { reachable: reachable, until: Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl }
        reachable
      end
    end

    # Drops the cached verdict, so the next caller asks the box again. For the
    # tests, and for a rake task that has just fixed the thing that was wrong.
    def forget_availability!
      @availability_lock.synchronize { @availability = nil }
    end

    # What the far side reports about itself: torch, CUDA, the GPU's name, and
    # which tools are on its PATH. Used by the setup rake task, never by a job
    # -- importing torch to answer costs seconds.
    def probe
      call({ action: "probe" }, timeout_seconds: PROBE_TIMEOUT_SECONDS)
    end

    # One JSON request, one parsed JSON response, or nil when the far side
    # failed, timed out or could not be reached at all.
    #
    # The response goes via a temp file rather than a pipe: it is a few KB at
    # most, and a file cannot deadlock against a child that is writing more
    # than a pipe will hold while this process is still waiting to read it.
    def call(payload, timeout_seconds:, body: nil)
      return nil unless usable?

      Tempfile.create("karaoke-gpu-agent") do |file|
        status = run_agent(payload, body: body, out: file, timeout_seconds: timeout_seconds)
        return nil unless status&.success?

        file.rewind
        JSON.parse(file.read.lines.first.to_s)
      end
    rescue JSON::ParserError
      nil
    end

    # The one response that is not JSON: an artifact's bytes, written straight
    # from ssh's stdout into a local file so a 40MB stem never sits in Ruby's
    # heap. Returns true only when the far side also exited cleanly -- a
    # half-written file from a dropped connection is deleted rather than kept,
    # since a truncated mp3 would otherwise read as a finished artifact.
    def stream_to(payload, destination, timeout_seconds:)
      return false unless usable?

      FileUtils.mkdir_p(File.dirname(destination))
      partial = "#{destination}.gpu.part"

      status = File.open(partial, "wb") do |file|
        run_agent(payload, body: nil, out: file, timeout_seconds: timeout_seconds)
      end

      if status&.success? && File.size?(partial)
        FileUtils.mv(partial, destination)
        true
      else
        FileUtils.rm_f(partial)
        false
      end
    rescue SystemCallError => error
      Rails.logger.warn("[gpu] fetch of #{payload[:name]} failed: #{error.message}")
      FileUtils.rm_f(partial)
      false
    end

    private

    def ping_with_retries
      PING_BACKOFF_SECONDS.each_with_index do |delay, attempt|
        sleep(delay) if delay.positive?
        response = call({ action: "ping" }, timeout_seconds: PING_TIMEOUT_SECONDS)
        if response&.dig("ok")
          Rails.logger.info("[gpu] #{target} reachable (agent #{response['agent']}, #{response['platform']})")
          return true
        end

        Rails.logger.info("[gpu] #{target} did not answer (attempt #{attempt + 1}/#{PING_BACKOFF_SECONDS.size})")
      end

      Rails.logger.warn("[gpu] #{target} unreachable; karaoke work stays on this host")
      false
    end

    # Spawns one ssh, feeds it the request, and waits. `body` is an open file
    # whose bytes follow the JSON header on stdin -- how an upload works, and
    # the only case where stdin outgrows a pipe buffer and so has to be written
    # from its own thread while the child is already consuming it.
    #
    # Safe to call from several threads at once, and that happens: a prepare
    # runs the separation and the YouTube instrumental search concurrently.
    # Each call is its own connection and holds no state here.
    def run_agent(payload, body:, out:, timeout_seconds:)
      in_read, in_write = IO.pipe
      pid = Process.spawn(*ssh_command, in: in_read, out: out, err: File::NULL)
      in_read.close
      feeder = Thread.new { feed(in_write, payload, body) }

      TimedProcess.wait_for(pid, timeout_seconds: timeout_seconds).tap do |status|
        # Killed for the timeout: the feeder may still be blocked on a pipe
        # with no reader left, so it is not going to finish on its own.
        feeder.kill unless status
        feeder.join
      end
    end

    def ssh_command
      options = [
        "-T",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        # The box is on a ZeroTier LAN and identified by its address, so there
        # is no DNS trust to lean on either way; accept-new at least pins it
        # after the first connection instead of asking a question no background
        # job can answer.
        "-o", "StrictHostKeyChecking=accept-new",
        # A separation runs for minutes with nothing on the wire. Without these
        # a dropped ZeroTier link looks like a command that is still working,
        # right up until the timeout kills it.
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=4",
        "-o", "LogLevel=ERROR"
      ]
      key = ENV["KARAOKE_GPU_SSH_KEY"].presence
      options.push("-i", key, "-o", "IdentitiesOnly=yes") if key

      # python and agent are passed as separate arguments, which ssh joins with
      # a space into one remote command string -- parsed on that end by cmd.exe.
      # Left unquoted deliberately: quoting works in cmd.exe and sh but makes
      # PowerShell (if it has been made the DefaultShell) treat the program
      # path as a string expression rather than something to run. Unquoted
      # works in all three, at the price of not tolerating a space in either
      # path -- which karaoke:gpu:probe checks for and names.
      [ "ssh", *options, target, python, agent ]
    end

    def feed(pipe, payload, body)
      pipe.write("#{JSON.generate(payload)}\n")
      IO.copy_stream(body, pipe) if body
    rescue Errno::EPIPE
      # The far side rejected the header and exited; its stderr says why and
      # the exit status is what this method's caller acts on.
      nil
    ensure
      pipe.close unless pipe.closed?
    end
  end
end
