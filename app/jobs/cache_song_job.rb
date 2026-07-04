# Warms the MP3 cache for one song so pressing play on it is instant.
# Enqueued by the prepare endpoints; harmless to enqueue twice for the same
# ISRC (SongCache's per-ISRC lock and cached? check make the duplicate a no-op).
class CacheSongJob < ApplicationJob
  queue_as :default

  def perform(isrc)
    SongCache.ensure_cached(isrc)
  end
end
