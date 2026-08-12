# The phone half of the karaoke queue: search, tap, and the song is lined up
# on the TV.
#
# Deliberately outside the login service. The page itself carries no data — it
# is a shell that talks to KaraokeQueueController — so what it needs is to be
# reachable by a guest holding nothing but the code off the screen. Arriving
# with a valid one exchanges it for a cookie; arriving without gets the form
# that asks for it.
class KaraokeRemoteController < ApplicationController
  skip_before_action :require_login

  # A cookie, not a query parameter kept in the URL: the remote is left open on
  # a lock screen for a whole evening and reloaded a dozen times.
  COOKIE_DURATION = 1.day

  def show
    if params[:code].present?
      return unlock if KaraokeRemote.valid?(params[:code])

      @invalid_code = true
    end

    @unlocked = KaraokeRemote.valid?(cookies[:karaoke_remote])
  end

  private

  def unlock
    cookies[:karaoke_remote] = {
      value: params[:code].to_s.upcase,
      expires: COOKIE_DURATION.from_now,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    redirect_to karaoke_remote_path
  end
end
