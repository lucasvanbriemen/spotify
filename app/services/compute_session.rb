# One unit of karaoke work, and a scratch directory on whichever machine is
# going to do it.
#
# Everything expensive here is the same shape: run a binary that writes files.
# So rather than every caller branching on "GPU box or this host", they build
# their argv against a session -- naming files by `session.path("x.mp3")` and
# tools by `session.tool("yt-dlp")` -- and one of the two subclasses decides
# whether that means a local temp directory or a directory on the far side of
# an SSH connection.
#
#   ComputeSession.open("separate SW12345678") do |session|
#     session.put(local_lrc, "lyrics.lrc")
#     session.run(session.python, session.script("karaoke_separate.py"),
#                 session.path("original.mp3"), session.path("instrumental.wav"),
#                 outputs: %w[instrumental.wav], timeout_seconds: 1800)
#     session.fetch("instrumental.wav", destination)
#   end
#
# Two things follow from this that are worth stating. Success is decided by
# which files appeared, not by an exit status: yt-dlp exits non-zero when
# --max-downloads stops it, having produced exactly what was asked for. And
# the local path is not a separate, rarely-exercised fallback -- it is the same
# code as the remote one with a different back end, so a bug in the shared
# orchestration shows up either way round.
class ComputeSession
  # Stands in for the session's directory inside an argv entry. Substituted at
  # the point of running, by whichever side is going to run it, because the
  # remote directory's path is in Windows's syntax and no business of the
  # caller's.
  WORK = "{{work}}".freeze
  # Matches the agent's own cap: enough of a command's output to explain a
  # failure, not so much that a demucs progress bar is held in memory.
  OUTPUT_TAIL_BYTES = 4000

  # What a command did. `outputs` maps each declared filename that actually
  # appeared to its size, so callers ask `produced?` instead of stat-ing a path
  # they would otherwise have to know the location of.
  class Result
    attr_reader :outputs, :stdout, :stderr

    def initialize(ok:, outputs: {}, stdout: "", stderr: "", timed_out: false, seconds: nil)
      @ok = ok
      @outputs = outputs || {}
      @stdout = stdout.to_s
      @stderr = stderr.to_s
      @timed_out = timed_out
      @seconds = seconds
    end

    def ok? = @ok
    def timed_out? = @timed_out
    def seconds = @seconds
    def produced?(name) = @outputs.key?(name.to_s)

    # The last line of stdout, which is how the one command whose answer is its
    # output rather than its files (check_audio_alignment.py) is read.
    def last_line = @stdout.lines.map(&:strip).reject(&:empty?).last
  end

  # Opens a session on the GPU box when it answers, and on this host when it
  # does not. `label` only ever reaches the log, and is what tells you after
  # the fact which of the two ran a given song.
  #
  # `prefer_gpu: false` forces this host: what a caller passes when the GPU box
  # answered its ping and then failed the work anyway, and the same song is
  # being tried again here rather than given up on.
  def self.open(label = nil, prefer_gpu: true)
    session = prefer_gpu && GpuHost.available? ? Remote.new : Local.new
    Rails.logger.info("[compute] #{label} on #{session.where}")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      yield session
    ensure
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
      Rails.logger.info("[compute] #{label} finished on #{session.where} in #{elapsed}s")
      session.release
    end
  end

  # A path inside this session's directory, safe to put in an argv entry and to
  # hand back to #put, #fetch and #produced?.
  def path(name)
    "#{WORK}/#{name}"
  end

  def remote? = false
  def where = "this host"

  # The torch device demucs should use, or nil to let it choose. Only the GPU
  # box has anything better to name than the default.
  def device = ENV["KARAOKE_LOCAL_DEVICE"].presence

  def put(local_path, name) = raise(NotImplementedError)
  def run(*argv, outputs: [], timeout_seconds:, env: {}) = raise(NotImplementedError)
  def fetch(name, destination) = raise(NotImplementedError)
  def release = nil

  private

  # Every output of a command is declared before it runs, so both back ends
  # report the same thing and neither caller has to know where the files went.
  def tail(io)
    size = io.size
    io.seek([ size - OUTPUT_TAIL_BYTES, 0 ].max)
    io.read.to_s.force_encoding(Encoding::UTF_8).scrub
  rescue SystemCallError
    ""
  end
end
