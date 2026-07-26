# Builds the spoken text for each talk segment kind. News and DJ intros use
# the LLM; weather/time checks are deterministic templates (free, reliable,
# and impossible to hallucinate).
class TalkScripts
  NL_DAYS = %w[zondag maandag dinsdag woensdag donderdag vrijdag zaterdag].freeze
  NL_MONTHS = %w[januari februari maart april mei juni juli augustus september
                 oktober november december].freeze
  NL_HOURS = %w[twaalf één twee drie vier vijf zes zeven acht negen tien elf].freeze

  NEWS_SYSTEM = {
    "nl" => <<~PROMPT,
      Je schrijft nieuwsbulletins voor een kleine Nederlandse internetradiozender.
      Schrijf uitsluitend de gesproken tekst: geen opmaak, kopjes, aanhalingstekens of URL's.
      Toon: vlot en neutraal, zoals het NOS-radiojournaal.
      Lengte: 120 tot 200 woorden (ongeveer 45 tot 75 seconden spreektijd).
      Begin met "Het nieuws van <tijd>" en sluit af met een korte afkondiging.
      Schrijf getallen en afkortingen voluit zodat ze goed voorgelezen kunnen worden.
    PROMPT
    "en" => <<~PROMPT
      You write news bulletins for a small internet radio station.
      Write only the spoken text: no formatting, headings, quotation marks or URLs.
      Tone: brisk and neutral, like a BBC radio news summary.
      Length: 120 to 200 words (roughly 45 to 75 seconds of speech).
      Open with "The news at <time>" and close with a short sign-off.
      Write out numbers and abbreviations so they read aloud naturally.
    PROMPT
  }.freeze

  INTRO_SYSTEM = {
    "nl" => "Je bent een vriendelijke radio-dj op LTVB Radio. Schrijf één of twee " \
            "korte zinnen, uitsluitend gesproken tekst, zonder aanhalingstekens.",
    "en" => "You are a friendly radio DJ on LTVB Radio. Write one or two short " \
            "sentences, spoken text only, no quotation marks."
  }.freeze

  class << self
    def build(segment)
      case segment.kind
      when "news" then news(segment)
      when "intro" then intro(segment)
      when "weather" then weather(segment)
      end
    end

    private

    def news(segment)
      headlines = Array(segment.meta&.dig("headlines"))
      raise Openai::Client::Error, "no headlines on segment" if headlines.empty?

      now = local_time
      listing = headlines.each_with_index
        .map { |headline, i| "#{i + 1}. #{headline['title']} — #{headline['summary']}".strip }
        .join("\n")

      user = if segment.language == "nl"
        "Het is #{NL_DAYS[now.wday]} #{now.day} #{NL_MONTHS[now.month - 1]}, " \
        "#{now.strftime('%H:%M')} uur. De laatste NOS-headlines:\n#{listing}\n\n" \
        "Schrijf het bulletin."
      else
        "It is #{now.strftime('%A %-d %B')}, #{now.strftime('%H:%M')}. " \
        "The latest BBC headlines:\n#{listing}\n\nWrite the bulletin."
      end

      Openai::Client.complete(system: NEWS_SYSTEM.fetch(segment.language), user: user)
    end

    def intro(segment)
      prev_song = Song.find_by(isrc: segment.meta&.dig("prev_isrc"))
      next_song = Song.find_by(isrc: segment.meta&.dig("next_isrc"))
      return station_id_line(segment.language) unless prev_song && next_song

      user = if segment.language == "nl"
        "Zojuist gedraaid: #{prev_song.title} van #{prev_song.artist}. " \
        "Hierna: #{next_song.title} van #{next_song.artist}. Schrijf het praatje."
      else
        "Just played: #{prev_song.title} by #{prev_song.artist}. " \
        "Up next: #{next_song.title} by #{next_song.artist}. Write the link."
      end

      begin
        Openai::Client.complete(system: INTRO_SYSTEM.fetch(segment.language), user: user, max_tokens: 400)
      rescue Openai::Client::Error
        # Intros survive LLM outages on a static template.
        intro_template(segment.language, prev_song, next_song)
      end
    end

    def intro_template(language, prev_song, next_song)
      if language == "nl"
        "Dat was #{prev_song.title} van #{prev_song.artist}. Hierna: #{next_song.title} van #{next_song.artist}."
      else
        "That was #{prev_song.title} by #{prev_song.artist}. Up next: #{next_song.title} by #{next_song.artist}."
      end
    end

    def station_id_line(language)
      language == "nl" ? "Je luistert naar LTVB Radio." : "You're listening to LTVB Radio."
    end

    def weather(segment)
      conditions = Weather::Client.current
      airs_at = parse_airs_at(segment)
      degrees = conditions[:temperature].round

      if segment.language == "nl"
        "#{time_phrase_nl(airs_at)} Het is buiten #{degrees} graden en #{conditions[:description_nl]}. " \
        "Je luistert naar LTVB Radio."
      else
        "#{time_phrase_en(airs_at)} It's #{degrees} degrees outside with #{conditions[:description_en]}. " \
        "You're listening to LTVB Radio."
      end
    end

    def parse_airs_at(segment)
      stamp = segment.meta&.dig("airs_at")
      stamp ? Time.iso8601(stamp).in_time_zone(StationQueueBuilder::TIME_ZONE) : local_time
    rescue ArgumentError
      local_time
    end

    def local_time
      Time.current.in_time_zone(StationQueueBuilder::TIME_ZONE)
    end

    # Colloquial Dutch clock time ("ongeveer" because airs_at is an estimate,
    # rounded to 5 minutes by the queue builder).
    def time_phrase_nl(time)
      hour = NL_HOURS[time.hour % 12]
      next_hour = NL_HOURS[(time.hour + 1) % 12]

      phrase = case time.min
      when 0 then "#{hour} uur"
      when 5 then "vijf over #{hour}"
      when 10 then "tien over #{hour}"
      when 15 then "kwart over #{hour}"
      when 20 then "tien voor half #{next_hour}"
      when 25 then "vijf voor half #{next_hour}"
      when 30 then "half #{next_hour}"
      when 35 then "vijf over half #{next_hour}"
      when 40 then "tien over half #{next_hour}"
      when 45 then "kwart voor #{next_hour}"
      when 50 then "tien voor #{next_hour}"
      when 55 then "vijf voor #{next_hour}"
      else time.strftime("%H:%M") # unreachable with 5-minute rounding
      end

      "Het is ongeveer #{phrase}."
    end

    def time_phrase_en(time)
      "It's just about #{time.strftime('%-l:%M %p')}."
    end
  end
end
