# Runs a command to completion, killing it if it outlives timeout_seconds.
# Waits by polling (WNOHANG) rather than a single blocking Process.wait
# wrapped in Timeout.timeout: on Windows, that combination was observed to
# hang indefinitely when two such waits were in flight in the same process
# at once (karaoke's separation and the original song's yt-dlp download can
# now legitimately run concurrently for different songs).
module TimedProcess
  POLL_INTERVAL_SECONDS = 0.2

  def self.run(*command, env: {}, timeout_seconds:)
    wait(Process.spawn(env, *command, out: File::NULL, err: File::NULL), timeout_seconds:)
  end

  # Like .run, but returns the command's stdout (empty string on timeout or
  # a non-zero exit) instead of discarding it.
  def self.capture(*command, env: {}, timeout_seconds:)
    read, write = IO.pipe
    pid = Process.spawn(env, *command, out: write, err: File::NULL)
    write.close
    reader = Thread.new { read.read }

    status = wait(pid, timeout_seconds:)
    output = status ? reader.value : (reader.kill && "")
    read.close
    status ? output : ""
  end

  # The same bounded wait, for a caller that had to spawn the process itself.
  # GpuHost does: it wires ssh's stdin to a pipe it writes the request into and
  # ssh's stdout to the file the fetched artifact lands in, neither of which
  # .run or .capture can express. Returns the exit status, or nil if the
  # process had to be killed for outliving the timeout.
  def self.wait_for(pid, timeout_seconds:)
    wait(pid, timeout_seconds: timeout_seconds)
  end

  def self.wait(pid, timeout_seconds:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Process.kill("KILL", pid)
        Process.wait(pid)
        return nil
      end

      sleep POLL_INTERVAL_SECONDS
    end
  end
  private_class_method :wait
end
