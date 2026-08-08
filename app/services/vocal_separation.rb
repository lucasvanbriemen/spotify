# Produces a vocal-free instrumental + a reference pitch curve for a song.
# Mirrors SongCache: same per-ISRC file lock, same "readiness is whatever's
# on disk" model — there's no separate state to keep in sync.
#
# The pitch curve (for scoring) always comes from Demucs + librosa run on
# the original recording's isolated vocal stem — script/karaoke_separate.py.
# The instrumental (what actually plays back) prefers a real karaoke/
# instrumental upload found on YouTube, since those are properly mastered
# and Demucs's own split-apart accompaniment track has audible separation
# artifacts by comparison; Demucs's output is only the fallback when no
# matching upload exists. The two searches run concurrently since neither
# depends on the other. The isolated vocal stem itself is never written
# outside a temp directory (see the script) — it never touches this cache.
class VocalSeparation
  AUDIO_DIR = SongCache::AUDIO_DIR
  # Demucs on a CPU can take several minutes per song, and the first run
  # also downloads its pretrained weights (~80MB).
  SEPARATE_TIMEOUT_SECONDS = 1800
  ALIGNMENT_CHECK_TIMEOUT_SECONDS = 60
  # A YouTube upload starting even a second off from the original would
  # desync lyrics and scoring for the rest of the song.
  ALIGNMENT_TOLERANCE_SECONDS = 0.75
  # Demucs is CPU-heavy enough that running several at once mostly just
  # makes all of them slower rather than finishing sooner (observed:
  # queuing several songs made an unrelated one appear to hang — it hadn't,
  # its download was just waiting its turn behind others' Demucs runs on a
  # contended machine). One at a time, system-wide; the lighter YouTube
  # search for a different song can still proceed while this waits.
  DEMUCS_MUTEX = Mutex.new

  class << self
    def instrumental_path(isrc)
      AUDIO_DIR.join("#{isrc}.instrumental.mp3")
    end

    def pitch_path(isrc)
      AUDIO_DIR.join("#{isrc}.pitch.json")
    end

    def ready?(isrc)
      instrumental_path(isrc).file? && pitch_path(isrc).file?
    end

    def failed?(isrc)
      failed_marker(isrc).file?
    end

    # Ensures the original song is downloaded, then separates it. A per-ISRC
    # lock collapses concurrent callers (a prepare request and a background
    # retry) into one Demucs run instead of racing.
    def ensure_separated(isrc)
      return true if ready?(isrc)

      SongCache.ensure_cached(isrc)
      unless SongCache.cached?(isrc)
        FileUtils.mkdir_p(AUDIO_DIR)
        FileUtils.touch(failed_marker(isrc))
        return false
      end

      with_lock(isrc) do
        next true if ready?(isrc)

        FileUtils.rm_f(failed_marker(isrc))
        separate(isrc)
        next true if ready?(isrc)

        FileUtils.touch(failed_marker(isrc))
        false
      end
    end

    private

    def failed_marker(isrc)
      AUDIO_DIR.join("#{isrc}.separate.failed")
    end

    def with_lock(isrc)
      FileUtils.mkdir_p(AUDIO_DIR)
      File.open(AUDIO_DIR.join("#{isrc}.separate.lock"), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def separate(isrc)
      song = Song.find_by(isrc: isrc)
      tmp_wav = AUDIO_DIR.join("#{isrc}.instrumental.wav.tmp")
      youtube_mp3 = AUDIO_DIR.join("#{isrc}.instrumental.youtube.mp3")

      demucs_thread = Thread.new { run_demucs(isrc, tmp_wav) }
      youtube_thread = song && Thread.new { find_youtube_instrumental(song, youtube_mp3) }

      demucs_thread.join
      youtube_found = youtube_thread&.value || false
      youtube_found &&= tmp_wav.file? && aligned?(tmp_wav, youtube_mp3)

      if youtube_found
        FileUtils.mv(youtube_mp3, instrumental_path(isrc))
      elsif tmp_wav.file?
        encode_mp3(tmp_wav, instrumental_path(isrc))
      end
    ensure
      FileUtils.rm_f(tmp_wav)
      FileUtils.rm_f(youtube_mp3)
    end

    def run_demucs(isrc, tmp_wav)
      command = [
        python_executable.to_s,
        Rails.root.join("script/karaoke_separate.py").to_s,
        SongCache.path(isrc).to_s,
        tmp_wav.to_s,
        pitch_path(isrc).to_s
      ]
      DEMUCS_MUTEX.synchronize { TimedProcess.run(*command, timeout_seconds: SEPARATE_TIMEOUT_SECONDS) }
    end

    def find_youtube_instrumental(song, out_path)
      YoutubeKaraokeFinder.download(artist: song.artist, title: song.title, duration: song.duration, out_path: out_path)
    rescue StandardError
      false
    end

    # Compares onset timing against Demucs's own accompaniment track, which
    # is guaranteed sample-aligned with the original (same source file, no
    # time-stretching) — so any offset found here is the YouTube upload's,
    # not measurement noise.
    def aligned?(reference_wav, candidate_mp3)
      offset = TimedProcess.capture(
        python_executable.to_s, Rails.root.join("script/check_audio_alignment.py").to_s,
        reference_wav.to_s, candidate_mp3.to_s,
        timeout_seconds: ALIGNMENT_CHECK_TIMEOUT_SECONDS
      )
      offset.present? && offset.to_f.abs <= ALIGNMENT_TOLERANCE_SECONDS
    rescue StandardError
      false
    end

    def encode_mp3(wav_path, mp3_path)
      ffmpeg = ExecutablePath.resolve("ffmpeg")
      system(ffmpeg.to_s, "-y", "-i", wav_path.to_s, "-b:a", "192k", mp3_path.to_s, out: File::NULL, err: File::NULL)
    end

    # The dedicated venv at vendor/karaoke/ (see README.md's Notes section
    # for setup) — mirrors vendor/kokoro/'s existing pattern for the TTS
    # fallback rather than depending on a system Python.
    def python_executable
      windows = Rails.root.join("vendor/karaoke/Scripts/python.exe")
      windows.exist? ? windows : Rails.root.join("vendor/karaoke/bin/python")
    end
  end
end
