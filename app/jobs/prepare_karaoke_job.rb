# Downloads and vocal-separates one song for karaoke. Enqueued by the
# prepare endpoint; harmless to enqueue twice for the same ISRC
# (VocalSeparation's per-ISRC lock and ready? check make the duplicate a no-op).
class PrepareKaraokeJob < ApplicationJob
  # Its own queue: a separation occupies a worker thread for minutes, and on
  # the shared one that starves the radio's news/TTS/caching jobs behind it.
  queue_as :karaoke

  def perform(isrc)
    VocalSeparation.ensure_separated(isrc)
  end
end
