# Karaoke results: what each singer scored on a song, and what they have to
# beat next time. Follows StatsController#store_play — one cheap insert per
# performance, aggregated on read.
class KaraokeScoresController < ApiController
  include ValidatesIsrc

  before_action :require_valid_isrc, except: :history

  BEST_LIMIT = 10
  RECENT_LIMIT = 10
  SECTION_LIMIT = 10

  # POST /api/karaoke/:isrc/scores — one call per singer, from the results
  # screen. Answers with the personal-best comparison so the screen can say
  # "new best" without a second round trip.
  def create
    score = KaraokeScore.new(
      song_isrc: isrc,
      singer_name: params[:singer_name],
      score: params[:score],
      accuracy: params[:accuracy],
      meta: meta_param
    )

    if score.save
      render json: score_json(score).merge(
        personal_best: personal_best?(score),
        best_score: KaraokeScore.where(song_isrc: isrc, singer_name: score.singer_name).maximum(:score)
      ), status: :created
    else
      render json: { errors: score.errors }, status: :unprocessable_entity
    end
  end

  # GET /api/karaoke/:isrc/scores — the leaderboard for one song.
  def index
    best = KaraokeScore.where(song_isrc: isrc)
      .group(:singer_name)
      .select("singer_name, MAX(score) AS score, MAX(created_at) AS created_at")
      .order("score DESC")
      .limit(BEST_LIMIT)

    render json: {
      best: best.map { |row| { singer_name: row.singer_name, score: row.score.to_i, created_at: row.created_at } },
      recent: KaraokeScore.where(song_isrc: isrc).order(created_at: :desc).limit(RECENT_LIMIT).map { |score| score_json(score) }
    }
  end

  # GET /api/karaoke-history — what to show on the search screen before anyone
  # has typed anything: the whole downloaded library (every song already
  # separated, so it starts instantly), plus what was sung recently.
  #
  # The ready list is uncapped: it is the library, and a library you cannot
  # see all of is one you end up searching for things you already have.
  def history
    recent = grouped_songs("MAX(created_at) DESC")
    ready_isrcs = VocalSeparation.prepared_isrcs

    isrcs = (recent.map(&:song_isrc) + ready_isrcs).uniq
    songs = Song.where(isrc: isrcs).index_by(&:isrc)

    render json: {
      # An artifact can outlive its Song row; a "ready" entry nobody can
      # recognise (or select — search won't find it) is left out.
      ready: ready_isrcs.select { |isrc| songs[isrc] }.map { |isrc| song_entry(isrc, songs, ready: true) },
      recent: recent.map { |row| history_entry(row, songs) }
    }
  end

  private

  def grouped_songs(order)
    KaraokeScore.group(:song_isrc)
      .select("song_isrc, COUNT(*) AS sing_count, MAX(created_at) AS last_sung_at")
      .order(Arel.sql(order))
      .limit(SECTION_LIMIT)
      .to_a
  end

  def history_entry(row, songs)
    song_entry(row.song_isrc, songs, ready: VocalSeparation.ready?(row.song_isrc))
      .merge(sing_count: row.sing_count.to_i)
  end

  # A prepared song may never have been sung, so there is no score row to
  # describe it — only the song and its artifacts.
  def song_entry(isrc, songs, ready:)
    song = songs[isrc]

    {
      isrc: isrc,
      title: song&.title || "Unknown",
      artist: song&.artist || "Unknown Artist",
      image_url: song&.image_url,
      ready: ready,
      difficulty: VocalSeparation.difficulty(isrc)&.dig("level")
    }
  end

  def personal_best?(score)
    !KaraokeScore.where(song_isrc: score.song_isrc, singer_name: score.singer_name)
      .where.not(id: score.id)
      .where("score > ?", score.score)
      .exists?
  end

  # meta is stored opaque and never queried, so it needs no strong parameters —
  # every attribute is assigned explicitly above.
  def meta_param
    value = params[:meta]
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
  end

  # meta is deliberately left out: it can run to a few KB per performance and
  # nothing reading a list needs it.
  def score_json(score)
    {
      id: score.id,
      singer_name: score.singer_name,
      score: score.score,
      accuracy: score.accuracy,
      created_at: score.created_at
    }
  end
end
