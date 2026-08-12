# The karaoke web UI: a search box that only surfaces synced-lyrics tracks
# (see SpotifyController#karaoke_search) and a full-screen lyrics stage. All
# data loading happens client-side against the JSON API.
class KaraokeController < ApplicationController
  def index
    # What the "add songs from your phone" card on the search screen shows: the
    # code a guest types, and the link that carries it for anyone who can just
    # be sent one.
    @remote_code = KaraokeRemote.code
    # Two forms: the link carries the code for anyone who can be sent one, and
    # the bare address is what a guest across the room types by hand.
    @remote_url = karaoke_remote_url(code: @remote_code)
    @remote_display_url = karaoke_remote_url.sub(%r{\Ahttps?://}, "")
  end
end
