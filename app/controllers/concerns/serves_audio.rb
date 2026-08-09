# Shared by SpotifyController (original songs) and KaraokeTracksController
# (instrumentals): serves an MP3 file, letting Apache handle Range requests
# via X-Sendfile in production, or handling a single-range request itself
# in dev so seeking still works without it.
module ServesAudio
  extend ActiveSupport::Concern

  private

  def send_audio_file(path)
    return head :not_found unless path.file?

    if Rails.application.config.action_dispatch.x_sendfile_header.present?
      return send_file path, type: "audio/mpeg", disposition: "inline"
    end

    response.headers["Accept-Ranges"] = "bytes"
    ranges = Rack::Utils.get_byte_ranges(request.headers["Range"], path.size)
    if ranges&.one?
      range = ranges.first
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{path.size}"
      send_data File.binread(path, range.size, range.begin),
        type: "audio/mpeg", disposition: "inline", status: :partial_content
    else
      send_file path, type: "audio/mpeg", disposition: "inline"
    end
  end
end
