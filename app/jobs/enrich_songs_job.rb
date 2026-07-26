# Backfills genre/year/bpm for songs created before enrichment existed (and
# any rows the inline path missed). Runs every 10 minutes via recurring.yml
# and quiesces once the whole library is enriched.
class EnrichSongsJob < ApplicationJob
  queue_as :default

  # Two Deezer calls per song plus the sleep keeps the batch far under
  # Deezer's ~50 requests per 5 seconds limit.
  BATCH_SIZE = 40

  def perform
    Song.enrichment_pending.order(:created_at).limit(BATCH_SIZE).each do |song|
      SongEnrichment.enrich!(song)
      sleep 0.3
    end
  end
end
