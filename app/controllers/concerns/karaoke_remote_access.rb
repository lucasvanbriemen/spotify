# Lets a phone that knows tonight's join code (see KaraokeRemote) use the
# queue endpoints without a login-service account.
#
# Include this only in controllers where *every* action is queue shaped —
# listing, adding, removing, and the karaoke search behind them. The code is a
# party credential, not a login.
module KaraokeRemoteAccess
  extend ActiveSupport::Concern

  included do
    # One condition, deliberately. skip_before_action folds `only:` and `if:`
    # into a single `unless:` list, where they combine as OR — pairing them
    # here would skip the login check for everyone on those actions.
    skip_before_action :require_login, if: -> { karaoke_remote_guest? }
  end

  private

  def karaoke_remote_guest?
    KaraokeRemote.valid?(cookies[:karaoke_remote].presence || params[:code])
  end
end
