# Checks on the GPU box that karaoke offloads its expensive work to. Nothing
# here is needed to run the app -- with KARAOKE_GPU_SSH unset, every prepare
# simply happens locally as it always did -- but "is the offload actually
# working" is otherwise only answerable by preparing a song and reading the log.
namespace :karaoke do
  namespace :gpu do
    desc "Report what the GPU box says about itself (torch, CUDA, tools)"
    task probe: :environment do
      abort "KARAOKE_GPU_SSH is not set: karaoke work runs on this host." unless GpuHost.configured?

      puts "target:  #{GpuHost.target}"
      puts "root:    #{GpuHost.root || '(unset -- nothing can be run)'}"
      puts "python:  #{GpuHost.python}"
      puts "agent:   #{GpuHost.agent}"
      puts "device:  #{GpuHost.device}"
      puts

      GpuHost.unquotable_paths.each do |name, path|
        puts "WARNING: #{name} contains a space or a quote: #{path.inspect}"
        puts "  The remote command string cannot survive that. Move the checkout"
        puts "  somewhere without spaces (C:/karaoke/music), or set #{name} to a"
        puts "  path without any -- a Windows 8.3 short name works too."
        puts
      end

      report = GpuHost.probe
      abort "no answer from #{GpuHost.target}. Is it awake, and is the key authorized?" unless report

      report.each { |key, value| puts format("  %-14s %s", key, value.inspect) }
      puts
      if report["cuda"]
        puts "CUDA is available: separations will run on the #{report['gpu']}."
      else
        puts "WARNING: torch reports no CUDA on that box, so demucs would fall back to its"
        puts "CPU there -- probably slower than doing it here. #{report['torch_error']}".strip
      end
    end

    desc "Round-trip a real file through the GPU box: exec, put, fetch, release"
    task check: :environment do
      abort "KARAOKE_GPU_SSH is not set." unless GpuHost.configured?

      GpuHost.forget_availability!
      unless GpuHost.available?
        abort "#{GpuHost.target} did not answer its ping. Nothing else will work until it does."
      end
      puts "ping:    ok"

      payload = "the quick brown fox\n#{SecureRandom.hex(8)}"
      returned = nil

      ComputeSession.open("gpu:check") do |session|
        abort "expected a remote session; got a local one" unless session.remote?

        Tempfile.create("gpu-check") do |file|
          file.write(payload)
          file.flush
          abort "put failed" unless session.put(file.path, "probe.txt")
        end
        puts "put:     ok (#{payload.bytesize} bytes)"

        result = session.run(
          session.python, "-c",
          "import pathlib,sys;p=pathlib.Path(sys.argv[1]);p.with_name('copied.txt').write_bytes(p.read_bytes())",
          session.path("probe.txt"),
          outputs: [ "copied.txt" ], timeout_seconds: 60
        )
        abort "exec failed: #{result.stderr}" unless result.produced?("copied.txt")
        puts "exec:    ok (#{result.seconds}s on the far side)"

        Tempfile.create("gpu-check-back") do |file|
          abort "fetch failed" unless session.fetch("copied.txt", file.path)
          returned = File.read(file.path)
        end
        puts "fetch:   ok"

        # The tools a prepare actually shells out to, checked here rather than
        # discovered halfway through somebody's song.
        %w[yt-dlp ffmpeg].each do |name|
          found = session.run(session.tool(name), "--version", timeout_seconds: 60).ok?
          puts "#{name.ljust(8)} #{found ? 'ok' : "MISSING at #{session.tool(name)}"}"
        end

        demucs = session.run(session.python, "-c", "import demucs, librosa; print('ok')", timeout_seconds: 300)
        puts "demucs:  #{demucs.ok? ? 'ok' : "MISSING -- #{demucs.stderr.lines.last.to_s.strip}"}"
      end

      if returned == payload
        puts "\nround trip intact: #{GpuHost.target} is ready to take karaoke work."
      else
        abort "\nwhat came back is not what went out -- the transfer is corrupting data."
      end
    end
  end
end
