# A compact music-radio format clock. Queue chunks are built ahead of playback,
# so callers pass the estimated time the chunk will begin; each transition then
# asks the clock whether a scheduled element has just come due.
class RadioClock
  Slot = Data.define(:kind, :scheduled_at, :duo)

  SLOT_DEFINITIONS = [
    { minute: 2, kind: "news", grace: 10.minutes, duo: false },
    { minute: 17, kind: "intro", grace: 10.minutes, duo: false },
    { minute: 32, kind: "weather", grace: 10.minutes, duo: false },
    { minute: 47, kind: "intro", grace: 10.minutes, duo: true }
  ].freeze

  def initialize(station_id:, cache: Rails.cache)
    @station_id = station_id
    @cache = cache
  end

  def due_at(time)
    local_time = time.in_time_zone(StationQueueBuilder::TIME_ZONE)
    hour = local_time.beginning_of_hour

    SLOT_DEFINITIONS.filter_map do |definition|
      scheduled_at = hour + definition.fetch(:minute).minutes
      next if local_time < scheduled_at
      next if local_time > scheduled_at + definition.fetch(:grace)

      slot = Slot.new(
        kind: definition.fetch(:kind),
        scheduled_at: scheduled_at,
        duo: definition.fetch(:duo)
      )
      slot unless claimed?(slot)
    end.max_by(&:scheduled_at)
  end

  def claim(slot)
    @cache.write(cache_key(slot), true, expires_in: 2.hours)
  end

  private

  def claimed?(slot)
    @cache.read(cache_key(slot)).present?
  end

  def cache_key(slot)
    "radio/clock/#{@station_id}/#{slot.scheduled_at.strftime('%Y%m%d%H%M')}/#{slot.kind}"
  end
end
