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
#
# None of this necessarily happens on this machine. Every command runs through
# a ComputeSession, which is a scratch directory either here or on a box with a
# GPU — htdemucs is ~80% of a prepare and this server has no graphics card, so
# the same song is ~205s here against ~38s there. The wav-to-mp3 encodes happen
# wherever the separation did, so a 40MB stem never crosses the network; only
# the ~4MB mp3 that is actually served comes back. Which host ran a given song
# is in the log, tagged [compute].
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
  # Encoding an instrumental is seconds; the timeout is here to bound a
  # wedged ffmpeg, not to trim a slow one.
  ENCODE_TIMEOUT_SECONDS = 300

  # Filenames inside a ComputeSession's scratch directory. Fixed rather than
  # derived from the ISRC because nothing else is in there — and because a
  # pseudo-ISRC for a pasted YouTube link then never reaches a command line.
  ORIGINAL_NAME = "original.mp3".freeze
  LRC_NAME = "lyrics.lrc".freeze
  INSTRUMENTAL_WAV = "instrumental.wav".freeze
  INSTRUMENTAL_MP3 = "instrumental.mp3".freeze
  VOCALS_WAV = "vocals.wav".freeze
  VOCALS_MP3 = "vocals.mp3".freeze
  YOUTUBE_MP3 = "youtube.mp3".freeze
  PITCH_NAME = "pitch.json".freeze
  NOTES_NAME = "notes.json".freeze
  WORDS_NAME = "words.json".freeze

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
      reextract = vocals_path(isrc).file? && stored_pitch_version(previous) != PITCH_VERSION

      ComputeSession.open("upgrade #{isrc}") do |session|
        session.put(lrc, LRC_NAME) if lrc

        command = [ session.python, session.script("karaoke_separate.py") ]
        outputs = [ NOTES_NAME ]

        if reextract
          next false unless session.put(vocals_path(isrc), VOCALS_MP3)

          command.push("--reextract", session.path(VOCALS_MP3), "--pitch-out", session.path(PITCH_NAME))
          outputs.push(PITCH_NAME)
          timeout = REEXTRACT_TIMEOUT_SECONDS
        else
          next false unless session.put(pitch_path(isrc), PITCH_NAME)

          command.push("--reanalyze", session.path(PITCH_NAME))
          timeout = REANALYZE_TIMEOUT_SECONDS
        end

        command.push("--notes-out", session.path(NOTES_NAME))
        if lrc
          command.push("--words-out", session.path(WORDS_NAME), "--lrc", session.path(LRC_NAME))
          outputs.push(WORDS_NAME)
        end

        result = session.run(*command, outputs: outputs, timeout_seconds: timeout)
        # Judged on the notes it produced in this session rather than on a
        # notes.json being on disk, which an earlier version would have left
        # there regardless.
        next false unless result.produced?(NOTES_NAME)

        session.fetch(PITCH_NAME, pitch_path(isrc)) if result.produced?(PITCH_NAME)
        session.fetch(NOTES_NAME, notes_path(isrc))
        session.fetch(WORDS_NAME, words_path(isrc)) if result.produced?(WORDS_NAME)

        # The upgrade recomputes analysis, not provenance: whatever the original
        # separation recorded about its instrumental still holds.
        write_manifest(
          isrc,
          instrumental_source: previous["instrumental_source"] || "unknown",
          alignment_offset_seconds: previous["alignment_offset_seconds"].to_f
        )
        true
      end
    ensure
      FileUtils.rm_f(lrc_path(isrc))
    end

    def separate(isrc)
      song = Song.find_by(isrc: isrc)
      # Fetched before the threads start so the analysis has it: LRCLIB
      # responses are cached for a week and the call is capped at 5s, which is
      # nothing against a Demucs run.
      lrc = write_lrc_file(isrc, song)

      on_gpu = false
      ComputeSession.open("separate #{isrc}") do |session|
        on_gpu = session.remote?
        separate_in(session, isrc, song, lrc)
      end
      return true if ready?(isrc)

      # The box answered its ping and then could not do the work: a driver that
      # wants a reboot, a model file it never downloaded, VRAM a game is
      # holding. One attempt here before the singer is told no — a slow song is
      # a much better outcome than a missing one.
      return false unless on_gpu

      Rails.logger.warn("[gpu] separating #{isrc} failed on the GPU box; retrying on this host")
      ComputeSession.open("separate #{isrc} (local retry)", prefer_gpu: false) do |session|
        separate_in(session, isrc, song, lrc)
      end
      ready?(isrc)
    ensure
      FileUtils.rm_f(lrc_path(isrc))
    end

    # The pipeline itself, once somewhere to run it has been decided. Reads
    # nothing from disk beyond the two inputs it stages, and writes nothing to
    # storage/audio until a command has actually produced the artifact.
    def separate_in(session, isrc, song, lrc)
      return false unless session.put(SongCache.path(isrc), ORIGINAL_NAME)

      session.put(lrc, LRC_NAME) if lrc

      demucs_thread = Thread.new { run_demucs(session, lrc) }
      youtube_thread = song && Thread.new { find_youtube_instrumental(session, song) }

      separation = demucs_thread.value
      youtube_found = youtube_thread&.value || false
      offset = youtube_found && separation.produced?(INSTRUMENTAL_WAV) ? alignment_offset_of(session) : nil
      youtube_found = !offset.nil? && offset.abs <= ALIGNMENT_TOLERANCE_SECONDS

      if youtube_found
        session.fetch(YOUTUBE_MP3, instrumental_path(isrc))
      elsif separation.produced?(INSTRUMENTAL_WAV)
        encode(session, INSTRUMENTAL_WAV, INSTRUMENTAL_MP3) &&
          session.fetch(INSTRUMENTAL_MP3, instrumental_path(isrc))
      end

      # The guide vocal is only usable when it and the instrumental are the two
      # halves of one recording. A YouTube karaoke upload is a different master
      # — aligned at the start to within a second at best — so laying our stem
      # over it doubles the singer into a slap-back echo. Keep the stem only
      # when demucs produced both sides.
      if youtube_found
        FileUtils.rm_f(vocals_path(isrc))
      elsif separation.produced?(VOCALS_WAV)
        encode(session, VOCALS_WAV, VOCALS_MP3) && session.fetch(VOCALS_MP3, vocals_path(isrc))
      end

      session.fetch(PITCH_NAME, pitch_path(isrc)) if separation.produced?(PITCH_NAME)
      session.fetch(NOTES_NAME, notes_path(isrc)) if separation.produced?(NOTES_NAME)
      session.fetch(WORDS_NAME, words_path(isrc)) if separation.produced?(WORDS_NAME)

      # Not written at all when the instrumental never arrived: the manifest is
      # what readiness is judged on, so writing one now would serve a song that
      # has nothing to play.
      return false unless instrumental_path(isrc).file? && pitch_path(isrc).file? && notes_path(isrc).file?

      write_manifest(
        isrc,
        instrumental_source: youtube_found ? "youtube" : "demucs",
        # Stored rather than merely thresholded: the client shifts its clocks
        # by this, so even the tolerated residue stops desyncing the lyrics.
        alignment_offset_seconds: youtube_found ? offset : 0.0
      )
      true
    end

    def run_demucs(session, lrc)
      command = [
        session.python,
        session.script("karaoke_separate.py"),
        session.path(ORIGINAL_NAME),
        session.path(INSTRUMENTAL_WAV),
        session.path(PITCH_NAME),
        "--vocals-out", session.path(VOCALS_WAV),
        "--notes-out", session.path(NOTES_NAME)
      ]
      # Only a host with something better than its CPU names a device; on this
      # server demucs's own default (one thread per physical core) is already
      # the fastest thing available and raising it makes it slower.
      command.push("--device", session.device) if session.device
      command.push("--words-out", session.path(WORDS_NAME), "--lrc", session.path(LRC_NAME)) if lrc

      outputs = [ INSTRUMENTAL_WAV, VOCALS_WAV, PITCH_NAME, NOTES_NAME ]
      outputs.push(WORDS_NAME) if lrc

      # Still one at a time, and for the same reason it always was — except
      # that the contended resource is now the GPU's memory rather than this
      # box's cores. The lighter YouTube search still runs alongside it.
      DEMUCS_MUTEX.synchronize do
        session.run(*command, outputs: outputs, timeout_seconds: SEPARATE_TIMEOUT_SECONDS)
      end
    end

    # Encoded wherever the separation happened, which is the point: demucs
    # emits wavs, a 4:20 stereo one is ~45MB, and the mp3 that replaces it is
    # ~4MB. Doing this before the fetch keeps the wavs off the network entirely.
    def encode(session, wav_name, mp3_name)
      session.run(
        session.tool("ffmpeg"), "-y", "-i", session.path(wav_name),
        "-b:a", "192k", session.path(mp3_name),
        outputs: [ mp3_name ], timeout_seconds: ENCODE_TIMEOUT_SECONDS
      ).produced?(mp3_name)
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

    # Searched and downloaded on the same host as the separation, so the
    # candidate is already sitting next to demucs's own accompaniment track
    # when the alignment check compares the two.
    def find_youtube_instrumental(session, song)
      YoutubeKaraokeFinder.download(
        session: session, artist: song.artist, title: song.title,
        duration: song.duration, name: YOUTUBE_MP3
      )
    rescue StandardError
      false
    end

    # Compares onset timing against Demucs's own accompaniment track, which
    # is guaranteed sample-aligned with the original (same source file, no
    # time-stretching) — so any offset found here is the YouTube upload's,
    # not measurement noise. Positive means the upload runs behind the
    # original. nil when the measurement itself failed.
    def alignment_offset_of(session)
      result = session.run(
        session.python, session.script("check_audio_alignment.py"),
        session.path(INSTRUMENTAL_WAV), session.path(YOUTUBE_MP3),
        timeout_seconds: ALIGNMENT_CHECK_TIMEOUT_SECONDS
      )
      return nil unless result.ok?

      # The only command here whose answer is what it printed rather than what
      # it wrote: one number, on the last line.
      Float(result.last_line.to_s)
    rescue ArgumentError, TypeError
      nil
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
  end
end
