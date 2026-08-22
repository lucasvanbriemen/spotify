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

  # YouTube protects its media URLs with a JavaScript challenge (the "n"
  # parameter, and signature solving alongside it). yt-dlp ships the solver
  # scripts, but it needs a JavaScript engine to run them in — and it enables
  # *only* deno by default, so a box with Node and no deno reports
  # "JS runtimes: none" and quietly solves nothing. The symptom is not an
  # error about JavaScript: the challenge fails, every audio format is
  # withheld, and yt-dlp says "Only images are available for download" and
  # then "Requested format is not available" for every candidate in the
  # search. (Observed 2026-08-22: four songs queued at a party, every one
  # failing its download in about 45 seconds.)
  #
  # Overridable through YTDLP_JS_RUNTIMES — a runtime yt-dlp cannot find is
  # not fatal, it just puts us back to solving nothing, so a server with deno
  # instead of Node can be re-pointed without a deploy.
  DEFAULT_JS_RUNTIMES = "node".freeze

  class << self
    # Prepended to every invocation that has to come back with media, which is
    # every download. Metadata-only calls (--dump-json) do not need it: titles
    # and durations are not behind the challenge.
    def media_options
      runtimes = js_runtimes
      runtimes.present? ? [ "--js-runtimes", runtimes ] : []
    end

    def js_runtimes
      ENV.fetch("YTDLP_JS_RUNTIMES", DEFAULT_JS_RUNTIMES).to_s.strip
    end

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
