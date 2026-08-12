# The shared karaoke queue: what the room has lined up to sing next.
#
# Two very different clients talk to this. The karaoke screen polls #index to
# know what to play after the current song, and claims items with #update. The
# phones on /karaoke/remote add to it — which is why this controller (and only
# this controller) accepts tonight's join code in place of a login, and why its
# search lives here rather than reusing SpotifyController#karaoke_search.
class KaraokeQueueController < ApiController
  include KaraokeRemoteAccess

  # Enough for an evening, low enough that one bored guest can't fill the
  # table from a phone.
  MAX_WAITING = 60

  def index
    render json: queue_json
  end

  def create
    return head :bad_request unless params[:isrc].to_s.match?(KaraokeQueueItem::SONG_ISRC_FORMAT)

    if KaraokeQueueItem.waiting.count >= MAX_WAITING
      return render json: { error: "The queue is full — sing a few first." }, status: :unprocessable_entity
    end

    KaraokeQueueItem.prune_played
    item = KaraokeQueueItem.enqueue(
      song_isrc: params[:isrc],
      title: params[:title],
      artist: params[:artist],
      image_url: params[:image_url],
      added_by: params[:added_by]
    )

    return render json: { errors: item.errors }, status: :unprocessable_entity unless item.persisted?

    start_separation(item.song_isrc)
    render json: queue_json.merge(item: item_json(item)), status: :created
  end

  # Claiming ("playing") and releasing ("done") a song. The screen drives both
  # ends, so a phone watching the queue can show what is on stage right now.
  def update
    case params[:status]
    when "playing" then item.start!
    when "done" then item.finish!
    else return head :bad_request
    end

    render json: queue_json
  end

  def destroy
    item.destroy
    render json: queue_json
  end

  # Straight to the front — the "we're all waiting for this one" button.
  def promote
    item.promote!
    render json: queue_json
  end

  # Clears what is waiting, not what has been sung.
  def destroy_all
    KaraokeQueueItem.waiting.destroy_all
    render json: queue_json
  end

  # The remote's own search. Same source as the karaoke screen's, trimmed to
  # what a phone draws.
  def search
    query = params[:q].to_s.strip
    return render json: { songs: [] } if query.empty?

    render json: { songs: KaraokeSearch.results(query) }
  end

  private

  def item
    @item ||= KaraokeQueueItem.find(params[:id])
  end

  # Separation takes minutes. Starting it the moment a song is queued is what
  # lets the screen run back-to-back instead of stalling on every hand-off —
  # by the time the queue reaches this song it is usually already prepared.
  def start_separation(isrc)
    return if VocalSeparation.ready?(isrc)

    # An older attempt's failure marker would make #status answer "failed" for
    # this fresh one, and the screen stops polling on that (see
    # KaraokeTracksController#prepare).
    VocalSeparation.clear_failure(isrc)
    PrepareKaraokeJob.perform_later(isrc)
  end

  def queue_json
    now_playing = KaraokeQueueItem.now_playing

    {
      now_playing: now_playing && item_json(now_playing),
      items: KaraokeQueueItem.waiting.map { |row| item_json(row) }
    }
  end

  # ready tells the screen whether this song can start immediately, and the
  # remote whether to warn that it needs a few minutes first.
  def item_json(row)
    {
      id: row.id,
      isrc: row.song_isrc,
      title: row.title,
      artist: row.artist,
      image_url: row.image_url,
      added_by: row.added_by,
      status: row.status,
      ready: VocalSeparation.ready?(row.song_isrc)
    }
  end
end
