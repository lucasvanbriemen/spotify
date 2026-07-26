require "test_helper"

class RadioClockTest < ActiveSupport::TestCase
  setup do
    @station_id = "clock-test-#{SecureRandom.hex(4)}"
    @clock = RadioClock.new(
      station_id: @station_id,
      cache: ActiveSupport::Cache::MemoryStore.new
    )
    @zone = ActiveSupport::TimeZone[StationQueueBuilder::TIME_ZONE]
  end

  test "returns the most recent clock slot within its grace window" do
    slot = @clock.due_at(@zone.parse("2026-07-26 14:20:00"))

    assert_equal "intro", slot.kind
    assert_equal @zone.parse("2026-07-26 14:17:00"), slot.scheduled_at
    assert_not slot.duo
  end

  test "marks a claimed slot so a refill cannot schedule it twice" do
    time = @zone.parse("2026-07-26 14:49:00")
    slot = @clock.due_at(time)

    assert_equal "intro", slot.kind
    assert slot.duo

    @clock.claim(slot)

    assert_nil @clock.due_at(time)
  end

  test "does not backfill a stale slot outside its grace window" do
    assert_nil @clock.due_at(@zone.parse("2026-07-26 14:13:00"))
  end
end
