# Shared yt-dlp invocation details for the two things that download audio:
# SongCache (the original recording) and YoutubeKaraokeFinder (a ready-made
# instrumental).
#
# YouTube answers the extractor's default player client with a blanket
# "HTTP Error 403: Forbidden" on some networks. Metadata extraction still
# works, so a search finds five perfectly good candidates and then fails to
# download every one of them — which reaches the singer as "Couldn't prepare
# this song for karaoke", with nothing to say why. (Observed for Green Day's
# "When I Come Around": five results inside the duration window, five 403s.)
#
# Which player clients still serve audio changes whenever YouTube moves, so a
# download walks a list rather than trusting one, and the list is overridable
# through YTDLP_PLAYER_CLIENTS so a server can be re-pointed without a deploy.
module YtDlp
  # Tried in order; the first that produces a file wins. "default" means "pass
  # no --extractor-args at all" — it is kept last so the built-in choice is
  # still used when the ones above it stop working, rather than being the thing
  # every download waits on while it 403s.
  DEFAULT_PLAYER_CLIENTS = %w[ web_embedded tv_simply default ].freeze

  class << self
    # One entry per attempt: the extra arguments that select that attempt's
    # player client. Callers run their command once per entry and stop as soon
    # as the file they wanted exists.
    def download_attempts
      player_clients.map do |client|
        client == "default" ? [] : [ "--extractor-args", "youtube:player_client=#{client}" ]
      end
    end

    def player_clients
      configured = ENV["YTDLP_PLAYER_CLIENTS"].to_s.split(",").map(&:strip).reject(&:empty?)
      configured.presence || DEFAULT_PLAYER_CLIENTS
    end
  end
end
