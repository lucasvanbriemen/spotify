# Karaoke playback backend: the vocal-free instrumental, the isolated vocal
# stem behind the guide fader, and the analysis artifacts the stage draws and
# scores against (pitch curve, quantized notes, word timings) — all produced by
# VocalSeparation. Separation takes minutes, so unlike SpotifyController#get_mp3
# (which blocks the request on yt-dlp), the frontend calls #prepare then polls
# #status rather than waiting on one long request.
class KaraokeTracksController < ApiController
  include ServesAudio
  include ValidatesIsrc

  before_action :require_valid_isrc

  def prepare
    return head :ok if VocalSeparation.ready?(isrc)

    # A previous attempt's failure marker would otherwise make #status answer
    # "failed" for this fresh attempt, and the client stops polling on that.
    VocalSeparation.clear_failure(isrc)
    PrepareKaraokeJob.perform_later(isrc)
    head :accepted
  end

  def status
    return render json: { ready: false, stage: stage } unless VocalSeparation.ready?(isrc)

    # artifacts tells the client which optional features this song supports —
    # a song upgraded from an older cache has no vocal stem, so no guide fader.
    render json: {
      ready: true,
      stage: "ready",
      artifacts: VocalSeparation.artifacts(isrc),
      difficulty: VocalSeparation.difficulty(isrc),
      # How far the instrumental runs behind the recording the lyrics/notes
      # were timed to (YouTube uploads only); the engine shifts its clocks by it.
      alignment_offset_seconds: VocalSeparation.alignment_offset(isrc)
    }
  end

  def instrumental
    send_audio_file(VocalSeparation.instrumental_path(isrc))
  end

  def vocals
    send_audio_file(VocalSeparation.vocals_path(isrc))
  end

  def pitch
    send_json_artifact(VocalSeparation.pitch_path(isrc))
  end

  def notes
    send_json_artifact(VocalSeparation.notes_path(isrc))
  end

  def words
    send_json_artifact(VocalSeparation.words_path(isrc))
  end

  private

  # Each artifact 404s on its own rather than gating on ready?, so the stage
  # degrades one feature at a time: a missing words file just means the client
  # estimates word timings itself. Cached for a day but still revalidated —
  # the URL isn't versioned, and clearing the cache regenerates the contents.
  def send_json_artifact(path)
    return head :not_found unless path.file?

    expires_in 1.day, public: false
    return unless stale?(last_modified: path.mtime.utc)

    send_file path, type: "application/json", disposition: "inline"
  end

  # What to tell a client that is still waiting. Also the place a dropped job
  # gets noticed: Solid Queue fails a pruned job outright rather than raising
  # inside it, so ActiveJob's retries never see it and PrepareKaraokeJob has no
  # retry_on to catch it either. A worker that dies mid-prep — an OOM kill, a
  # deploy, a restart — therefore used to leave the song with no job, no failure
  # marker, and a client polling "downloading" forever. (Observed 2026-08-21:
  # the worker unit was oom-killed three times in three minutes and every song
  # queued from a phone hung on step 1.)
  def stage
    return "failed" if VocalSeparation.failed?(isrc)

    case prepare_job_state
    when :none
      # Enqueuing from a GET, deliberately: this is the only request that
      # notices, and the poll is what makes it self-healing. Safe to race with
      # another client's poll — the job is idempotent by design (per-ISRC lock
      # plus a ready? check), and the :none guard keeps it from queueing twice.
      PrepareKaraokeJob.perform_later(isrc)
      "queued"
    when :waiting then "queued"
    else SongCache.cached?(isrc) ? "separating" : "downloading"
    end
  end

  # :none, :waiting (enqueued, no worker has it yet) or :running. The
  # karaoke queue runs one job at a time, so :waiting is the common and
  # otherwise invisible case — a song sitting behind another song's Demucs run,
  # which is exactly what "stuck downloading" looked like from the sofa.
  #
  # A job that died counts as :none, not as one still to come. Solid Queue
  # leaves finished_at nil on a job it failed, so a killed prepare stays
  # "unfinished" for ever — 16 of them were sitting on production when this was
  # written, every one an OOM casualty. Without where.missing(:failed_execution)
  # this would answer :waiting for exactly the songs it exists to rescue, and
  # the screen would say "queued" until someone gave up.
  #
  # Reads Solid Queue's own tables; StatsController#queue_healthy? does the
  # same. The ISRC is already checked against /\A[a-zA-Z0-9-]+\z/ by
  # ValidatesIsrc's before_action, so it carries no LIKE metacharacters.
  def prepare_job_state
    jobs = SolidQueue::Job.where(class_name: "PrepareKaraokeJob", finished_at: nil)
                          .where("arguments LIKE ?", "%#{isrc}%")
                          .where.missing(:failed_execution)
    return :none unless jobs.exists?

    jobs.joins(:claimed_execution).exists? ? :running : :waiting
  rescue StandardError
    # A queue we cannot read is not grounds for enqueuing another job.
    :running
  end
end
