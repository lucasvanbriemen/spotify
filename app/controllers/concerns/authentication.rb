require "net/http"

module Authentication
  extend ActiveSupport::Concern

  LOGIN_URL = "https://login.ltvb.nl"

  # Matches the Laravel app's 10-day auth cookie.
  AUTH_COOKIE_DURATION = 10.days

  included do
    before_action :require_login
    helper_method :current_account
  end

  private

  attr_reader :current_account

  def require_login
    token = auth_token
    @current_account = fetch_account(token) if token.present?

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
