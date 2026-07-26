require "test_helper"

class StationQueueBuilderTest < ActiveSupport::TestCase
  test "variable presenter links use a two-to-seven song range" do
    assert_equal 2..7, StationQueueBuilder::INTRO_GAP
  end
end
