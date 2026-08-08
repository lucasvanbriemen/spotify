# Karaoke playback backend: a vocal-free instrumental plus its reference
# pitch curve, produced by VocalSeparation (Demucs + librosa). Separation
# takes minutes, so unlike SpotifyController#get_mp3 (which blocks the
# request on yt-dlp), the frontend calls #prepare then polls #status rather
# than waiting on one long request.
class KaraokeTracksController < ApiController
  include ServesAudio

  ISRC_FORMAT = /\A[a-zA-Z0-9-]+\z/

  def prepare
    return head :bad_request unless valid_isrc?
    return head :ok if VocalSeparation.ready?(isrc)

    PrepareKaraokeJob.perform_later(isrc)
    head :accepted
  end

  def status
    return head :bad_request unless valid_isrc?

    render json: { ready: VocalSeparation.ready?(isrc), stage: stage }
  end

  def instrumental
    return head :bad_request unless valid_isrc?

    send_audio_file(VocalSeparation.instrumental_path(isrc))
  end

  def pitch
    return head :bad_request unless valid_isrc?
    return head :not_found unless VocalSeparation.ready?(isrc)

    send_file VocalSeparation.pitch_path(isrc), type: "application/json", disposition: "inline"
  end

  private

  def isrc
    params[:isrc]
  end

  def valid_isrc?
    isrc.match?(ISRC_FORMAT)
  end

  def stage
    return "ready" if VocalSeparation.ready?(isrc)
    return "failed" if VocalSeparation.failed?(isrc)

    SongCache.cached?(isrc) ? "separating" : "downloading"
  end
end
