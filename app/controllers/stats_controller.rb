# Play tracking and listening stats (port of the Laravel StatsController).
class StatsController < ApiController
  def store_play
    # Talk segments are not songs: recording them would pollute the stats (and
    # fail the songs FK anyway). Ack without persisting so the client path
    # stays uniform.
    return head :no_content if TalkSegment.talk_id?(params[:isrc])

    play = Play.new(
      song_isrc: params[:isrc],
      seconds_played: params[:seconds_played],
      station_id: params[:station_id].presence
    )

    if play.save
      render json: play, status: :created
    else
      render json: { errors: play.errors }, status: :unprocessable_entity
    end
  end

  def index
    top = Play.group(:song_isrc)
      .select("song_isrc, COUNT(*) AS play_count, SUM(seconds_played) AS seconds_played")
      .order("play_count DESC")
      .limit(5)
      .to_a
    songs_by_isrc = Song.where(isrc: top.map(&:song_isrc)).index_by(&:isrc)

    top_songs = top.map do |row|
      song = songs_by_isrc[row.song_isrc]

      {
        isrc: row.song_isrc,
        title: song&.title || "Unknown",
        artist: song&.artist || "Unknown Artist",
        image_url: song&.image_url,
        play_count: row.play_count.to_i,
        seconds_played: row.seconds_played.to_i
      }
    end

    render json: {
      total_plays: Play.count,
      unique_songs: Play.distinct.count(:song_isrc),
      total_seconds_played: Play.sum(:seconds_played).to_i,
      top_songs: top_songs,
      # Everything radio (news bulletins, warmups, enrichment) depends on the
      # Solid Queue worker, which Passenger doesn't supervise — surface its
      # health where it's easy to spot from the app.
      queue_healthy: queue_healthy?
    }
  end

  private

  def queue_healthy?
    SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists?
  rescue StandardError
    false
  end
end
