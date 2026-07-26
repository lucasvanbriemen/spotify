ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# Every controller runs Authentication#require_login, which validates the
# bearer token against login.ltvb.nl over HTTP. Tests stub the lookup so no
# network call happens; requests still need to send a token (see AUTH_HEADERS).
module StubbedAuthentication
  private

  def fetch_account(_token)
    { "name" => "test" }
  end
end
ApplicationController.prepend(StubbedAuthentication)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    AUTH_HEADERS = { "Authorization" => "Bearer test-token" }.freeze

    # Add more helper methods to be used by all tests here...
  end
end
