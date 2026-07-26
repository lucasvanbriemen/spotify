# Radio stations: the station list and the continuous play queue the app
# refills from while a station is playing.
class StationsController < ApiController
  def index
    render json: { stations: Station.all.map(&:as_json) }
  end

  def queue
    station = Station.find(params[:id])
    count = params.fetch(:count, 10).to_i.clamp(1, 25)

    render json: {
      station: station.as_json,
      items: StationQueueBuilder.new(station, count: count, base_url: request.base_url).build
    }
  rescue Station::NotFound
    head :not_found
  end
end
