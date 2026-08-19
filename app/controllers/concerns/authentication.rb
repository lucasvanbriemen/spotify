require "net/http"

module Authentication
  extend ActiveSupport::Concern

  LOGIN_URL = "https://login.ltvb.nl"

  # Matches Token::TOKEN_DURATION in the login app.
  AUTH_COOKIE_DURATION = 1.week

  included do
    before_action :require_login
    helper_method :current_account
  end

  private

  attr_reader :current_account

  def require_login
    token = auth_token
    @current_account = local_dev_account || (fetch_account(token) if token.present?)

    if @current_account.nil?
      return redirect_to "#{LOGIN_URL}?redirect=#{CGI.escape(request.original_url)}", allow_other_host: true
    end

    # Token arrived via the URL (login redirect); persist it as a cookie and clean the URL.
    if params[:auth_token].present?
      store_auth_cookie(token)
      redirect_to clean_url
    end
  end

  def auth_token
    cookies[:auth_token].presence || params[:auth_token].presence || request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
  end

  # A dev machine has no business round-tripping through the production login
  # service to open the karaoke screen — and on a laptop that can't reach it,
  # every request redirects off-site instead. LOCAL_DEV_ACCOUNT (set in .env)
  # stands in for the session locally.
  #
  # Gated on Rails.env.development? as well as the variable, so the same
  # variable reaching a deployed environment cannot open it up.
  def local_dev_account
    return nil unless Rails.env.development?

    name = ENV["LOCAL_DEV_ACCOUNT"].presence
    name && { "id" => 0, "name" => name, "email" => "#{name.parameterize}@localhost" }
  end

  def fetch_account(token)
    response = Net::HTTP.get_response(URI("#{LOGIN_URL}/session/#{token}"))
    return nil unless response.is_a?(Net::HTTPOK)

    JSON.parse(response.body)
  end

  def store_auth_cookie(token)
    cookies[:auth_token] = {
      value: token,
      expires: AUTH_COOKIE_DURATION.from_now,
      httponly: true,
      secure: Rails.env.production?,
      domain: :all
    }
  end

  def clean_url
    remaining = request.query_parameters.except("auth_token")
    remaining.empty? ? request.path : "#{request.path}?#{remaining.to_query}"
  end
end
