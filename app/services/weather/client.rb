require "net/http"

module Weather
  class Error < StandardError; end

  # Current conditions from the keyless open-meteo API, cached briefly — radio
  # weather checks don't need minute precision.
  class Client
    URL = "https://api.open-meteo.com/v1/forecast"
    TIMEOUT_SECONDS = 5
    CACHE_TTL = 15.minutes

    # WMO weather interpretation codes -> spoken description.
    DESCRIPTIONS = {
      0 => { "nl" => "onbewolkt", "en" => "clear skies" },
      1 => { "nl" => "vrijwel onbewolkt", "en" => "mostly clear" },
      2 => { "nl" => "half bewolkt", "en" => "partly cloudy" },
      3 => { "nl" => "bewolkt", "en" => "overcast" },
      45 => { "nl" => "mistig", "en" => "foggy" },
      48 => { "nl" => "mistig", "en" => "foggy" },
      51 => { "nl" => "lichte motregen", "en" => "light drizzle" },
      53 => { "nl" => "motregen", "en" => "drizzle" },
      55 => { "nl" => "dichte motregen", "en" => "heavy drizzle" },
      56 => { "nl" => "ijzel", "en" => "freezing drizzle" },
      57 => { "nl" => "ijzel", "en" => "freezing drizzle" },
      61 => { "nl" => "lichte regen", "en" => "light rain" },
      63 => { "nl" => "regen", "en" => "rain" },
      65 => { "nl" => "zware regen", "en" => "heavy rain" },
      66 => { "nl" => "ijzel", "en" => "freezing rain" },
      67 => { "nl" => "ijzel", "en" => "freezing rain" },
      71 => { "nl" => "lichte sneeuw", "en" => "light snow" },
      73 => { "nl" => "sneeuw", "en" => "snow" },
      75 => { "nl" => "zware sneeuw", "en" => "heavy snow" },
      77 => { "nl" => "sneeuw", "en" => "snow grains" },
      80 => { "nl" => "lichte buien", "en" => "light showers" },
      81 => { "nl" => "buien", "en" => "showers" },
      82 => { "nl" => "zware buien", "en" => "heavy showers" },
      85 => { "nl" => "sneeuwbuien", "en" => "snow showers" },
      86 => { "nl" => "sneeuwbuien", "en" => "snow showers" },
      95 => { "nl" => "onweer", "en" => "thunderstorms" },
      96 => { "nl" => "onweer met hagel", "en" => "thunderstorms with hail" },
      99 => { "nl" => "onweer met hagel", "en" => "thunderstorms with hail" }
    }.freeze

    class << self
      # -> { temperature: Float, description_nl: String, description_en: String }
      def current
        Rails.cache.fetch("weather/current", expires_in: CACHE_TTL) { fetch_current }
      end

      private

      def fetch_current
        uri = URI(URL)
        uri.query = URI.encode_www_form(
          latitude: ENV.fetch("STATION_LAT", "52.37"),
          longitude: ENV.fetch("STATION_LON", "4.89"),
          current: "temperature_2m,weather_code"
        )
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
          open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        raise Error, "open-meteo failed (#{response.code})" unless response.is_a?(Net::HTTPOK)

        current = JSON.parse(response.body)["current"] || raise(Error, "open-meteo payload missing current")
        code = current["weather_code"].to_i
        {
          temperature: current["temperature_2m"].to_f,
          description_nl: DESCRIPTIONS.dig(code, "nl") || "wisselvallig",
          description_en: DESCRIPTIONS.dig(code, "en") || "changeable"
        }
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "open-meteo failed: #{e.message}"
      end
    end
  end
end
