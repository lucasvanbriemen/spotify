# Shared ISRC handling for the karaoke API. The format check is also what makes
# the value safe to join onto a cached-file path — no slashes, no "..".
#
# Wider than a real ISRC (12 alphanumerics) because two other kinds of id ride
# the same routes: TalkSegment's "talk-..." and YoutubeTrack's "yt-<video id>",
# whose eleven-character ids can contain underscores.
module ValidatesIsrc
  extend ActiveSupport::Concern

  ISRC_FORMAT = /\A[a-zA-Z0-9_-]+\z/

  private

  def isrc
    params[:isrc]
  end

  def valid_isrc?
    isrc.to_s.match?(ISRC_FORMAT)
  end

  def require_valid_isrc
    head :bad_request unless valid_isrc?
  end
end
