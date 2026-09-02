# Produces everything the karaoke stage needs for a song. Mirrors SongCache:
# same per-ISRC file lock, same "readiness is whatever's on disk" model.
#
# One demucs run yields all of it. The pitch curve, the quantized note list
# (for the pitch lane and per-note scoring) and the per-word timings always
# come from librosa run on the original recording's isolated vocal stem — see
# script/karaoke_separate.py. The instrumental (what actually plays back)
# prefers a real karaoke/instrumental upload found on YouTube, since those are
# properly mastered and demucs's own split-apart accompaniment track has
# audible separation artifacts by comparison; demucs's output is only the
# fallback when no matching upload exists. The two searches run concurrently
# since neither depends on the other.
#
# The isolated vocal stem is now kept as <isrc>.vocals.mp3 — it is what the
# stage's vocal-guide fader plays back, quietly, over the instrumental. This
# deliberately reverses the earlier guarantee that the stem never left a temp
# directory (the script's docstring is updated to match).
class VocalSeparation
  AUDIO_DIR = SongCache::AUDIO_DIR
  # Demucs on a CPU can take several minutes per song, and the first run
  # also downloads its pretrained weights (~80MB).
  SEPARATE_TIMEOUT_SECONDS = 1800
  # Recomputing notes/words from an existing pitch curve is pure arithmetic.
  REANALYZE_TIMEOUT_SECONDS = 120
  ALIGNMENT_CHECK_TIMEOUT_SECONDS = 60
  # How far a YouTube instrumental may start from the original before it is
  # rejected. The lyrics are timed to the original, so any offset accepted here
  # would be heard as the words landing early or late for the whole song —
  # which is why the measured value is no longer merely thresholded but stored
  # in the manifest, so the client can shift its clocks by it and the words
  # land on the beat regardless.
  ALIGNMENT_TOLERANCE_SECONDS = 0.25
  # Re-running pyin over a whole vocal stem takes tens of seconds on a CPU —
  # far less than Demucs, far more than pure reanalysis.
  REEXTRACT_TIMEOUT_SECONDS = 600
  # Bump when an artifact's format changes or a new required one is added:
  # caches written by an older version are upgraded on their next prepare
  # instead of being served half-ready.
  # 3: pitch curves rescue loud-but-harmonised sections pyin calls unvoiced,
  #    the note fence is octave-aware, words.json strips duet markers, and the
  #    manifest records the YouTube instrumental's alignment offset.
  # 4: notes and word timings are fenced to where the lyrics say singing
  #    happens, so a lead instrument Demucs left in the vocal stem stops being
  #    played as the guide melody and counted into the perfect score.
  ARTIFACT_VERSION = 4
  # Bumped only when *pitch extraction itself* changes — which is a far rarer
  # event than an artifact bump, and a far more expensive one to act on.
  # Everything downstream of the curve (notes, words) is recomputed from the
  # stored pitch.json in about a second; re-extracting the curve means running
  # pyin over the whole vocal stem again, tens of seconds a song. Without this,
  # every artifact bump re-extracted every song that still had its stem: 56 of
  # the 80 on prod at v4, for a change that touched neither pyin nor its input.
  #
  # A manifest from before this was recorded is read as version 1 when it is
  # v3 or newer, because v3 is exactly where the current extraction (the
  # rescue passes for loud harmonised sections) landed.
  PITCH_VERSION = 1
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

    def vocals_path(isrc)
      AUDIO_DIR.join("#{isrc}.vocals.mp3")
    end

    def pitch_path(isrc)
      AUDIO_DIR.join("#{isrc}.pitch.json")
    end

    def notes_path(isrc)
      AUDIO_DIR.join("#{isrc}.notes.json")
    end

    def words_path(isrc)
      AUDIO_DIR.join("#{isrc}.words.json")
    end

    def manifest_path(isrc)
      AUDIO_DIR.join("#{isrc}.karaoke.json")
    end

    # Playback, the pitch lane and scoring all need these three; the vocal
    # stem and word timings are optional extras the stage degrades without.
    def ready?(isrc)
      manifest = read_manifest(isrc)
      return false unless manifest && manifest["version"] == ARTIFACT_VERSION

      instrumental_path(isrc).file? && pitch_path(isrc).file? && notes_path(isrc).file?
    end

    def failed?(isrc)
      failed_marker(isrc).file?
    end

    # Called when a retry is enqueued. The marker is otherwise only cleared
    # once the job reaches the lock, and until then #status keeps reporting
    # "failed" — which stops the client polling, so the song never comes back
    # even though it is being prepared right then.
    def clear_failure(isrc)
      FileUtils.rm_f(failed_marker(isrc))
    end

    # Which optional artifacts this song actually got, so the client can hide
    # the features it can't support (no vocals -> no guide fader).
    def artifacts(isrc)
      read_manifest(isrc)&.dig("artifacts") || {}
    end

    def difficulty(isrc)
      read_manifest(isrc)&.dig("difficulty")
    end

    # Seconds the instrumental runs behind the recording the lyrics and notes
    # were timed against — non-zero only for YouTube-sourced instrumentals.
    # The client shifts its display and scoring clocks by it.
    def alignment_offset(isrc)
      read_manifest(isrc)&.dig("alignment_offset_seconds").to_f
    end

    # Every song that would start instantly, most recently prepared first.
    # Readiness lives on disk (a manifest per ISRC), so this is a glob, not a
    # query — fine at living-room scale, and the only place that lists it.
    def prepared_isrcs
      Dir.glob(AUDIO_DIR.join("*.karaoke.json"))
        .sort_by { |path| -File.mtime(path).to_f }
        .map { |path| File.basename(path).delete_suffix(".karaoke.json") }
        .select { |isrc| ready?(isrc) }
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
        upgrade_legacy(isrc) || separate(isrc)
        next true if ready?(isrc)

        FileUtils.touch(failed_marker(isrc))
        false
      end
    end

    private

    # See PITCH_VERSION. 0 for a manifest old enough that its curve predates
    # the current extraction, which is the one case worth paying pyin for.
    def stored_pitch_version(manifest)
      recorded = manifest["pitch_version"]
      return recorded.to_i if recorded

      manifest["version"].to_i >= 3 ? 1 : 0
    end

    def failed_marker(isrc)
      AUDIO_DIR.join("#{isrc}.separate.failed")
    end

    def lrc_path(isrc)
      AUDIO_DIR.join("#{isrc}.lrc.tmp")
    end

    def script_path
      Rails.root.join("script/karaoke_separate.py")
    end

    def with_lock(isrc)
      FileUtils.mkdir_p(AUDIO_DIR)
      File.open(AUDIO_DIR.join("#{isrc}.separate.lock"), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    # An outdated cache already holds the expensive part: the instrumental.
    # Everything else can be regenerated without Demucs — which would turn
    # every previously instant song into a multi-minute wait the first time it
    # was picked. Songs that kept their vocal stem get a fresh pitch curve
    # from it (--reextract picks up rescue passes the stored curve predates);
    # older ones (the stem used to be deleted) recompute notes and words from
    # the stored curve. Deleting the instrumental forces a full re-separation.
    def upgrade_legacy(isrc)
      return false unless instrumental_path(isrc).file?
      return false unless vocals_path(isrc).file? || pitch_path(isrc).file?

      previous = read_manifest(isrc) || {}
      lrc = write_lrc_file(isrc)

      command = [ python_executable.to_s, script_path.to_s ]
      if vocals_path(isrc).file? && stored_pitch_version(previous) != PITCH_VERSION
        command.push("--reextract", vocals_path(isrc).to_s, "--pitch-out", pitch_path(isrc).to_s)
        timeout = REEXTRACT_TIMEOUT_SECONDS
      else
        command.push("--reanalyze", pitch_path(isrc).to_s)
        timeout = REANALYZE_TIMEOUT_SECONDS
      end
      command.push("--notes-out", notes_path(isrc).to_s)
      command.push("--words-out", words_path(isrc).to_s, "--lrc", lrc.to_s) if lrc

      TimedProcess.run(*command, timeout_seconds: timeout)
      return false unless notes_path(isrc).file?

      # The upgrade recomputes analysis, not provenance: whatever the original
      # separation recorded about its instrumental still holds.
      write_manifest(
        isrc,
        instrumental_source: previous["instrumental_source"] || "unknown",
        alignment_offset_seconds: previous["alignment_offset_seconds"].to_f
      )
      true
    ensure
      FileUtils.rm_f(lrc_path(isrc))
    end

    def separate(isrc)
      song = Song.find_by(isrc: isrc)
      tmp_wav = AUDIO_DIR.join("#{isrc}.instrumental.wav.tmp")
      tmp_vocals = AUDIO_DIR.join("#{isrc}.vocals.wav.tmp")
      youtube_mp3 = AUDIO_DIR.join("#{isrc}.instrumental.youtube.mp3")

      # Fetched before the threads start so the analysis has it: LRCLIB
      # responses are cached for a week and the call is capped at 5s, which is
      # nothing against a Demucs run.
      lrc = write_lrc_file(isrc, song)

      demucs_thread = Thread.new { run_demucs(isrc, tmp_wav, tmp_vocals, lrc) }
      youtube_thread = song && Thread.new { find_youtube_instrumental(song, youtube_mp3) }

      demucs_thread.join
      youtube_found = youtube_thread&.value || false
      offset = youtube_found && tmp_wav.file? ? alignment_offset_of(tmp_wav, youtube_mp3) : nil
      youtube_found = !offset.nil? && offset.abs <= ALIGNMENT_TOLERANCE_SECONDS

      if youtube_found
        FileUtils.mv(youtube_mp3, instrumental_path(isrc))
      elsif tmp_wav.file?
        encode_mp3(tmp_wav, instrumental_path(isrc))
      end

      # The guide vocal is only usable when it and the instrumental are the two
      # halves of one recording. A YouTube karaoke upload is a different master
      # — aligned at the start to within a second at best — so laying our stem
      # over it doubles the singer into a slap-back echo. Keep the stem only
      # when demucs produced both sides.
      if youtube_found
        FileUtils.rm_f(vocals_path(isrc))
      elsif tmp_vocals.file?
        encode_mp3(tmp_vocals, vocals_path(isrc))
      end

      write_manifest(
        isrc,
        instrumental_source: youtube_found ? "youtube" : "demucs",
        # Stored rather than merely thresholded: the client shifts its clocks
        # by this, so even the tolerated residue stops desyncing the lyrics.
        alignment_offset_seconds: youtube_found ? offset : 0.0
      )
    ensure
      FileUtils.rm_f(tmp_wav)
      FileUtils.rm_f(tmp_vocals)
      FileUtils.rm_f(youtube_mp3)
      FileUtils.rm_f(lrc_path(isrc))
    end

    def run_demucs(isrc, tmp_wav, tmp_vocals, lrc)
      command = [
        python_executable.to_s,
        script_path.to_s,
        SongCache.path(isrc).to_s,
        tmp_wav.to_s,
        pitch_path(isrc).to_s,
        "--vocals-out", tmp_vocals.to_s,
        "--notes-out", notes_path(isrc).to_s
      ]
      command.push("--words-out", words_path(isrc).to_s, "--lrc", lrc.to_s) if lrc

      DEMUCS_MUTEX.synchronize { TimedProcess.run(*command, timeout_seconds: SEPARATE_TIMEOUT_SECONDS) }
    end

    # The script takes the LRC as a file rather than fetching it: lyrics are
    # already cached here, and Python has no business calling LRCLIB.
    def write_lrc_file(isrc, song = Song.find_by(isrc: isrc))
      return nil unless song

      synced = Lrclib::Client.fetch(
        artist: song.artist, title: song.title, album: song.album, duration: song.duration
      )["syncedLyrics"]
      return nil if synced.blank?

      lrc_path(isrc).write(synced)
      lrc_path(isrc)
    rescue StandardError
      nil
    end

    def find_youtube_instrumental(song, out_path)
      YoutubeKaraokeFinder.download(artist: song.artist, title: song.title, duration: song.duration, out_path: out_path)
    rescue StandardError
      false
    end

    # Compares onset timing against Demucs's own accompaniment track, which
    # is guaranteed sample-aligned with the original (same source file, no
    # time-stretching) — so any offset found here is the YouTube upload's,
    # not measurement noise. Positive means the upload runs behind the
    # original. nil when the measurement itself failed.
    def alignment_offset_of(reference_wav, candidate_mp3)
      offset = TimedProcess.capture(
        python_executable.to_s, Rails.root.join("script/check_audio_alignment.py").to_s,
        reference_wav.to_s, candidate_mp3.to_s,
        timeout_seconds: ALIGNMENT_CHECK_TIMEOUT_SECONDS
      )
      offset.present? ? offset.to_f : nil
    rescue StandardError
      nil
    end

    def encode_mp3(wav_path, mp3_path)
      ffmpeg = ExecutablePath.resolve("ffmpeg")
      system(ffmpeg.to_s, "-y", "-i", wav_path.to_s, "-b:a", "192k", mp3_path.to_s, out: File::NULL, err: File::NULL)
    end

    # Written last, and atomically: a crash partway through leaves no manifest
    # at all, so the song reads as not-ready and is retried, rather than
    # appearing ready with a missing piece.
    def write_manifest(isrc, instrumental_source:, alignment_offset_seconds: 0.0)
      payload = {
        "version" => ARTIFACT_VERSION,
        "pitch_version" => PITCH_VERSION,
        "created_at" => Time.current.utc.iso8601,
        "instrumental_source" => instrumental_source,
        "alignment_offset_seconds" => alignment_offset_seconds.to_f.round(3),
        "artifacts" => {
          "instrumental" => instrumental_path(isrc).file?,
          "pitch" => pitch_path(isrc).file?,
          "notes" => notes_path(isrc).file?,
          "vocals" => vocals_path(isrc).file?,
          "words" => words_path(isrc).file?
        },
        "difficulty" => KaraokeDifficulty.summary(read_json(notes_path(isrc)))
      }

      tmp = AUDIO_DIR.join("#{isrc}.karaoke.json.tmp")
      tmp.write(JSON.generate(payload))
      FileUtils.mv(tmp, manifest_path(isrc))
    end

    def read_manifest(isrc)
      read_json(manifest_path(isrc))
    end

    def read_json(path)
      return nil unless path.file?

      JSON.parse(path.read)
    rescue JSON::ParserError
      nil
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
