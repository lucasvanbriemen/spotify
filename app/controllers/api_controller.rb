# Base class for the JSON API consumed by the iOS app and (eventually) the
# web client. Requests authenticate with the login-service token (see
# Authentication), not a CSRF-protected session.
class ApiController < ApplicationController
  skip_forgery_protection
end
