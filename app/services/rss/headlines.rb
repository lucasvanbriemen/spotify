require "net/http"
require "rss"

module Rss
  class Error < StandardError; end

  # Latest headlines for the news bulletins: NOS for Dutch, BBC for English.
  class Headlines
    FEEDS = {
      "nl" => "https://feeds.nos.nl/nosnieuwsalgemeen",
      "en" => "https://feeds.bbci.co.uk/news/rss.xml"
    }.freeze
    TIMEOUT_SECONDS = 5

    class << self
      # -> [{ "title" =>, "summary" => }] (string keys: stored in a json column)
      def fetch(language, limit: 6)
        url = FEEDS.fetch(language) { raise Error, "no feed for #{language}" }
        feed = RSS::Parser.parse(get(url), false)
        raise Error, "empty feed" if feed.nil? || feed.items.empty?

        feed.items.first(limit).map do |item|
          {
            "title" => clean(item.title),
            "summary" => clean(item.description)
          }
        end
      rescue RSS::Error => e
        raise Error, "feed parse failed: #{e.message}"
      end

      private

      def clean(text)
        ActionController::Base.helpers.strip_tags(text.to_s).squish
      end

      def get(url, redirects_left = 2)
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end

        if response.is_a?(Net::HTTPRedirection) && redirects_left.positive?
          return get(response["location"], redirects_left - 1)
        end
        raise Error, "feed fetch failed (#{response.code})" unless response.is_a?(Net::HTTPOK)

        response.body
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "feed fetch failed: #{e.message}"
      end
    end
  end
end
