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

    render json: {
      station: station.as_json,
      items: StationQueueBuilder.new(
        station,
        count: count,
        base_url: request.base_url,
        starts_in: starts_in
      ).build
    }
  rescue Station::NotFound
    head :not_found
  end
end
