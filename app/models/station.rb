# A radio station: a named slice of the library that StationQueueBuilder
# samples from. Stations are code-defined and computed from song metadata and
# play history rather than stored in the database — genre and decade stations
# appear automatically once enough enriched songs exist, and the smart
# stations are tunable right here.
class Station
  class NotFound < StandardError; end

  # A genre/decade needs at least this many songs to become a station; smart
  # stations are hidden below a lower bar so dead cards never show up.
  MIN_SONGS = 15
  MIN_SMART_SONGS = 5
  LIST_CACHE_TTL = 5.minutes

  class << self
    def all
      Rails.cache.fetch("stations/all", expires_in: LIST_CACHE_TTL) do
        smart_stations + genre_stations + decade_stations
      end
    end

    def find(id)
      all.find { |station| station.id == id } || raise(NotFound, "unknown station #{id}")
    end

    private

    def smart_stations
      [
        new(id: "smart-morning", name: "Morning", kind: :smart),
        new(id: "smart-party", name: "Party", kind: :smart),
        new(id: "smart-focus", name: "Focus", kind: :smart),
        new(id: "smart-discovery", name: "Discovery", kind: :smart)
      ].select { |station| station.song_count >= MIN_SMART_SONGS }
    end

    def genre_stations
      Song.where.not(genre: nil).group(:genre).count
        .select { |_genre, count| count >= MIN_SONGS }
        .sort_by { |_genre, count| -count }
        .map { |genre, _count| new(id: "genre-#{genre.parameterize}", name: genre, kind: :genre, param: genre) }
    end

    def decade_stations
      Song.where.not(release_year: nil).pluck(:release_year)
        .map { |year| year / 10 * 10 }.tally
        .select { |_decade, count| count >= MIN_SONGS }
        .sort.map do |decade, _count|
          label = format("%02ds", decade % 100)
          new(id: "decade-#{label}", name: label, kind: :decade, param: decade)
        end
    end
  end

  attr_reader :id, :name, :kind, :param

  def initialize(id:, name:, kind:, param: nil)
    @id = id
    @name = name
    @kind = kind
    @param = param
  end

  def candidate_songs
    case kind
    when :genre then Song.where(genre: param)
    when :decade then Song.where(release_year: param..(param + 9))
    when :smart then smart_candidates
    end
  end

  def song_count
    @song_count ||= candidate_songs.count
  end

  # Station artwork: borrow a cover from the station's own songs.
  def image_url
    @image_url ||= candidate_songs.where.not(image_url: [ nil, "" ]).order(:isrc).limit(1).pluck(:image_url).first
  end

  def language
    "en"
  end

  # Talk policy: Focus stays quiet, Discovery only gets track intros.
  def news?
    !%w[smart-focus smart-discovery].include?(id)
  end

  def intros?
    id != "smart-focus"
  end

  # Sampling weights for the queue builder; nil means a plain shuffle.
  def weights(songs)
    case id
    when "smart-morning" then morning_weights(songs)
    when "smart-party" then party_weights(songs)
    end
  end

  def as_json(*)
    {
      id: id,
      name: name,
      kind: kind.to_s,
      language: language,
      song_count: song_count,
      image_url: image_url
    }
  end

  private

  def smart_candidates
    case id
    when "smart-morning" then Song.all
    when "smart-party" then Song.where(bpm: 115..).or(Song.where(deezer_rank: 500_000..))
    when "smart-focus" then Song.where(bpm: 1..110)
    when "smart-discovery" then rarely_played_songs
    end
  end

  def rarely_played_songs
    played_repeatedly = Play.group(:song_isrc).having("COUNT(*) > 1").pluck(:song_isrc)
    Song.where.not(isrc: played_repeatedly)
  end

  # Boost songs that historically play in the morning hours. Hour-of-day must
  # be computed in local time, in Ruby: the app runs on UTC and MariaDB's
  # timezone tables are often unloaded (so no CONVERT_TZ).
  def morning_weights(songs)
    morning_counts = Play.pluck(:song_isrc, :created_at).each_with_object(Hash.new(0)) do |(isrc, played_at), counts|
      hour = played_at.in_time_zone(StationQueueBuilder::TIME_ZONE).hour
      counts[isrc] += 1 if (6..10).cover?(hour)
    end
    return nil if morning_counts.empty?

    songs.index_with { |song| 1.0 + morning_counts[song.isrc] * 3.0 }
  end

  # Energy plus familiarity: fast songs the listener actually plays.
  def party_weights(songs)
    play_counts = Play.group(:song_isrc).count

    songs.index_with do |song|
      1.0 + (song.bpm.to_f / 40.0) + Math.log10(1 + play_counts[song.isrc].to_i)
    end
  end
end
