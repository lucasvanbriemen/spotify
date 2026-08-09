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
      difficulty: VocalSeparation.difficulty(isrc)
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

  def stage
    return "failed" if VocalSeparation.failed?(isrc)

    SongCache.cached?(isrc) ? "separating" : "downloading"
  end
end
