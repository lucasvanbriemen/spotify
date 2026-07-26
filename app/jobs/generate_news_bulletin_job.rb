# Writes and voices the hourly news bulletin for one language. Scheduled via
# config/recurring.yml just after the top of the hour; the id carries the
# local hour so each bulletin airs at most for that hour.
class GenerateNewsBulletinJob < ApplicationJob
  queue_as :default

  def perform(language)
    hour_stamp = Time.current.in_time_zone(StationQueueBuilder::TIME_ZONE).strftime("%Y%m%d%H")
    id = "talk-news-#{language}-#{hour_stamp}"
    return if TalkSegment.find_by(id: id)&.ready?

    headlines = Rss::Headlines.fetch(language)
    segment = TalkSegment.find_or_initialize_by(id: id)
    segment.assign_attributes(
      kind: "news",
      language: language,
      status: "pending",
      expires_at: 24.hours.from_now,
      meta: { "headlines" => headlines }
    )
    segment.save!

    TalkAudio.ensure_rendered(id)
  rescue Rss::Error => e
    # No feed, no bulletin: stations degrade to music-only via the queue
    # builder's freshness check.
    Rails.logger.warn("news bulletin (#{language}) skipped: #{e.message}")
  end
end
