# Builds one chunk of a station's play queue: a weighted sample of songs with
# spoken segments (news bulletin, DJ intros, weather/time checks) interleaved
# per the station's talk policy. Items come out in the exact JSON shape the
# app already decodes for songs, plus kind: "song"|"talk" — talk audio then
# plays through the ordinary get-mp3 path.
class StationQueueBuilder
  RECENT_WINDOW = 6.hours     # don't repeat anything played recently
  NEWS_COOLDOWN = 18.minutes  # at most one bulletin per ~15-20 min of listening
  NEWS_MAX_AGE = 55.minutes   # only air the current hour's bulletin
  WEATHER_COOLDOWN = 45.minutes
  INTRO_EVERY = 3             # a DJ link roughly every third transition
  ESTIMATED_INTRO_SECONDS = 12
  ESTIMATED_WEATHER_SECONDS = 20
  ESTIMATED_NEWS_SECONDS = 60
  WARMUP_SONGS = 3
  TIME_ZONE = "Europe/Amsterdam"

  TALK_TITLES = {
    "news" => { "nl" => "Het nieuws", "en" => "The News" },
    "intro" => { "nl" => "LTVB Radio", "en" => "LTVB Radio" },
    "weather" => { "nl" => "Het weer", "en" => "Weather check" }
  }.freeze

  def initialize(station, count:, base_url:)
    @station = station
    @count = count
    @base_url = base_url
  end

  def build
    songs = sample_songs
    warm_cache(songs)

    begin
      with_talk(songs)
    rescue StandardError => e
      # A radio that plays music is always better than one that errors:
      # whatever goes wrong in the talk machinery, ship the songs.
      Rails.logger.warn("station talk interleaving failed: #{e.class}: #{e.message}")
      songs.map { |song| song_item(song) }
    end
  end

  private

  def sample_songs
    pool = @station.candidate_songs.to_a
    fresh = pool.reject { |song| recent_isrcs.include?(song.isrc) }
    # On small stations repeats beat silence: only exclude recent plays while
    # something is left to play.
    pool = fresh unless fresh.empty?

    weighted_sample(pool, @station.weights(pool))
  end

  def recent_isrcs
    @recent_isrcs ||= Play.where(created_at: RECENT_WINDOW.ago..).distinct.pluck(:song_isrc).to_set
  end

  # Sampling without replacement, so a chunk never contains the same song
  # twice. nil weights = plain shuffle.
  def weighted_sample(pool, weights)
    return pool.shuffle.first(@count) if weights.nil?

    remaining = pool.dup
    picks = []
    while picks.size < @count && remaining.any?
      target = rand * remaining.sum { |song| weights[song] || 1.0 }
      index = remaining.each_with_index do |song, i|
        target -= weights[song] || 1.0
        break i if target <= 0
      end
      picks << remaining.delete_at(index.is_a?(Integer) ? index : remaining.size - 1)
    end
    picks
  end

  def warm_cache(songs)
    songs.reject { |song| SongCache.cached?(song.isrc) }
      .first(WARMUP_SONGS)
      .each { |song| CacheSongJob.perform_later(song.isrc) }
  end

  def with_talk(songs)
    items = []
    elapsed = 0

    if @station.news? && (news = airable_news)
      items << talk_item(news, ESTIMATED_NEWS_SECONDS)
      elapsed += items.last[:duration]
    end

    weather_pending = @station.news? && !Tts::Client.down? && weather_due?
    intro_countdown = next_intro_countdown

    songs.each_with_index do |song, index|
      items << song_item(song)
      elapsed += song.duration.to_i

      next_song = songs[index + 1]
      next unless next_song

      if weather_pending
        segment = ensure_weather_segment(airs_at(elapsed))
        if segment
          items << talk_item(segment, ESTIMATED_WEATHER_SECONDS)
          elapsed += items.last[:duration]
          weather_pending = false
          next # never stack weather and an intro at the same transition
        end
      end

      next unless @station.intros? && !Tts::Client.down?

      intro_countdown -= 1
      next unless intro_countdown <= 0

      intro_countdown = next_intro_countdown
      segment = ensure_intro_segment(song, next_song)
      if segment
        items << talk_item(segment, ESTIMATED_INTRO_SECONDS)
        elapsed += items.last[:duration]
      end
    end

    items
  end

  def next_intro_countdown
    INTRO_EVERY + rand(-1..1)
  end

  # The freshest ready bulletin in the station's language, at most once per
  # cooldown across all stations of that language.
  def airable_news
    return nil unless Rails.cache.read(news_cooldown_key).nil?

    segment = TalkSegment.ready
      .where(kind: "news", language: @station.language)
      .where(created_at: NEWS_MAX_AGE.ago..)
      .order(created_at: :desc)
      .first
    return nil unless segment&.ready? # double-checks the audio file exists

    Rails.cache.write(news_cooldown_key, Time.current.to_i, expires_in: NEWS_COOLDOWN)
    segment
  end

  def news_cooldown_key
    "talk/news/#{@station.language}/queued_at"
  end

  def weather_due?
    Rails.cache.read(weather_cooldown_key).nil?
  end

  def weather_cooldown_key
    "talk/weather/#{@station.language}/queued_at"
  end

  def ensure_weather_segment(air_time)
    id = "talk-weather-#{@station.language}-#{air_time.strftime('%Y%m%d%H%M')}"
    segment = TalkSegment.find_or_create_by!(id: id) do |new_segment|
      new_segment.kind = "weather"
      new_segment.language = @station.language
      new_segment.expires_at = 6.hours.from_now
      new_segment.meta = { "airs_at" => air_time.iso8601 }
    end
    return nil if segment.status == "failed"

    GenerateTalkSegmentJob.perform_later(id) unless segment.ready?
    Rails.cache.write(weather_cooldown_key, Time.current.to_i, expires_in: WEATHER_COOLDOWN)
    segment
  end

  # Intros are keyed by the transition they announce, so re-requesting the
  # same chunk reuses the segment instead of generating it twice. Include the
  # presenter style version so a voice/delivery upgrade never replays an old
  # cached recording for that transition.
  def ensure_intro_segment(prev_song, next_song)
    key = [
      prev_song.isrc,
      next_song.isrc,
      @station.language,
      Tts::Client::STYLE_VERSION
    ].join("|")
    digest = Digest::SHA1.hexdigest(key)[0, 12]
    id = "talk-intro-#{digest}"
    segment = TalkSegment.find_or_create_by!(id: id) do |new_segment|
      new_segment.kind = "intro"
      new_segment.language = @station.language
      new_segment.expires_at = 6.hours.from_now
      new_segment.meta = { "prev_isrc" => prev_song.isrc, "next_isrc" => next_song.isrc }
    end
    return nil if segment.status == "failed"

    GenerateTalkSegmentJob.perform_later(id) unless segment.ready?
    segment
  end

  # Estimated local wall-clock time a slot this far into the chunk will air,
  # rounded to 5 minutes: stable ids and tolerant of refill-timing drift.
  def airs_at(elapsed_seconds)
    Time.at(((Time.current.to_i + elapsed_seconds) / 300.0).round * 300).in_time_zone(TIME_ZONE)
  end

  def song_item(song)
    {
      isrc: song.isrc,
      title: song.title,
      artist: song.artist.presence || "Unknown Artist",
      album: song.album,
      image_url: song.image_url.presence || Song::PLACEHOLDER_IMAGE,
      duration: song.duration.to_i,
      kind: "song"
    }
  end

  # Talk items ride the app's Song decoder: artist/image_url must never be
  # null and duration must be an integer (estimated until rendered).
  def talk_item(segment, estimated_duration)
    {
      isrc: segment.id,
      title: TALK_TITLES.dig(segment.kind, segment.language) || "LTVB Radio",
      artist: "LTVB Radio",
      album: @station.name,
      image_url: "#{@base_url}/radio/#{segment.kind}.png",
      duration: segment.duration || estimated_duration,
      kind: "talk",
      talk_kind: segment.kind
    }
  end
end
