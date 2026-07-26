require "test_helper"

module Tts
  module Providers
    class ElevenlabsTest < ActiveSupport::TestCase
      test "adds concise performance direction as an Eleven v3 audio tag" do
        directed = Elevenlabs.send(
          :directed_text,
          "That was the last record.",
          "casual, conversational, speaking off the cuff"
        )

        assert_equal(
          "[casual, conversational, speaking off the cuff] That was the last record.",
          directed
        )
      end
    end
  end
end
