require "zlib"

# Radio stations: the station list and the continuous play queue the app
# refills from while a station is playing.
class StationsController < ApiController
  def index
    render json: { stations: Station.all.map(&:as_json) }
  end

  def queue
    station = Station.find(params[:id])
    count = params.fetch(:count, 10).to_i.clamp(1, 25)
    starts_in = params.fetch(:starts_in, 0).to_i.clamp(0, 3_600)
    items = StationQueueBuilder.new(
      station,
      count: count,
      base_url: request.base_url,
      starts_in: starts_in
    ).build

    render json: {
      station: station.as_json,
      items: items,
      start_offset: starts_in.zero? ? live_join_offset(items.first, station.id) : 0
    }
  rescue Station::NotFound
    head :not_found
  end

  private

  # Radio is already on air when a listener tunes in. Start safely inside the
  # first record (never talk, never its final 30 seconds). The station-specific
  # phase makes simultaneous tune-ins feel consistent without storing session
  # state on the server.
  def live_join_offset(item, station_id)
    return 0 unless item&.fetch(:kind, nil) == "song"

    duration = item.fetch(:duration, 0).to_i
    return 0 if duration < 90

    earliest = 15
    latest = [ (duration * 0.65).floor, duration - 30 ].min
    return 0 if latest <= earliest

    earliest + ((Time.current.to_i + Zlib.crc32(station_id)) % (latest - earliest + 1))
  end
end
