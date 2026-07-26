require "test_helper"

class StationsControllerTest < ActiveSupport::TestCase
  test "live join starts safely inside a sufficiently long song" do
    controller = StationsController.new
    item = { kind: "song", duration: 240 }

    offset = controller.send(:live_join_offset, item, "genre-rock")

    assert_includes 15..156, offset
  end

  test "live join never seeks into talk or a short song" do
    controller = StationsController.new

    assert_equal 0, controller.send(:live_join_offset, { kind: "talk", duration: 60 }, "genre-rock")
    assert_equal 0, controller.send(:live_join_offset, { kind: "song", duration: 80 }, "genre-rock")
  end
end
