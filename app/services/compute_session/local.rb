# ComputeSession on this host: a temp directory under tmp/, and the binaries
# the app already ships in bin/ and vendor/.
#
# This is what ran before the GPU offload existed, reached through the session
# interface instead of directly. The extra cost over the old code is one copy
# per artifact out of tmp/ into storage/audio -- both under Rails.root, so the
# same filesystem, so milliseconds against a separation's minutes -- and in
# exchange the remote path is not a second implementation of the pipeline.
class ComputeSession::Local < ComputeSession
  WORK_ROOT = "tmp/karaoke-compute".freeze

  def initialize
    @work_dir = Rails.root.join(WORK_ROOT, SecureRandom.hex(8))
    FileUtils.mkdir_p(@work_dir)
  end

  def python
    # The dedicated venv at vendor/karaoke/ (see README's Notes section),
    # mirroring vendor/kokoro/ rather than depending on a system Python.
    windows = Rails.root.join("vendor/karaoke/Scripts/python.exe")
    (windows.exist? ? windows : Rails.root.join("vendor/karaoke/bin/python")).to_s
  end

  def tool(name) = ExecutablePath.resolve(name).to_s
  def script(name) = Rails.root.join("script", name).to_s
  def bin_dir = Rails.root.join("bin").to_s

  def put(local_path, name)
    return false unless local_path && File.file?(local_path.to_s)

    FileUtils.cp(local_path.to_s, resolve(path(name)))
    true
  end

  def run(*argv, outputs: [], timeout_seconds:, env: {})
    resolved = argv.map { |entry| resolve(entry.to_s) }

    Tempfile.create("karaoke-compute-out") do |out|
      Tempfile.create("karaoke-compute-err") do |err|
        status = TimedProcess.wait_for(
          Process.spawn(environment(env), *resolved, chdir: @work_dir.to_s, out: out, err: err),
          timeout_seconds: timeout_seconds
        )
        Result.new(
          ok: !!status&.success?, timed_out: status.nil?,
          stdout: tail(out), stderr: tail(err), outputs: staged(outputs)
        )
      end
    end
  end

  def fetch(name, destination)
    source = resolve(path(name))
    return false unless File.file?(source)

    FileUtils.mkdir_p(File.dirname(destination.to_s))
    # Copied then renamed rather than copied into place: an artifact half-way
    # through a copy is still a file, and readiness is decided by files being
    # there.
    partial = "#{destination}.local.part"
    FileUtils.cp(source, partial)
    FileUtils.mv(partial, destination.to_s)
    true
  rescue SystemCallError => error
    Rails.logger.warn("[compute] copying #{name} out failed: #{error.message}")
    FileUtils.rm_f("#{destination}.local.part")
    false
  end

  def release
    FileUtils.rm_rf(@work_dir)
  end

  private

  def resolve(entry)
    entry.gsub(WORK, @work_dir.to_s)
  end

  def staged(outputs)
    outputs.to_a.each_with_object({}) do |name, sizes|
      size = File.size?(resolve(path(name)))
      sizes[name.to_s] = size if size
    end
  end

  def environment(extra)
    # yt-dlp and demucs both scatter intermediates through the temp directory;
    # pointing it at the work directory is what makes #release clean those up
    # as well, and it is what SongCache did by hand before.
    {
      "TMP" => @work_dir.to_s, "TEMP" => @work_dir.to_s, "TMPDIR" => @work_dir.to_s
    }.merge(extra.transform_keys(&:to_s).transform_values { |value| resolve(value.to_s) })
  end
end
