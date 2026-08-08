# Downloads and vocal-separates one song for karaoke. Enqueued by the
# prepare endpoint; harmless to enqueue twice for the same ISRC
# (VocalSeparation's per-ISRC lock and ready? check make the duplicate a no-op).
class PrepareKaraokeJob < ApplicationJob
  queue_as :default

  def perform(isrc)
    VocalSeparation.ensure_separated(isrc)
  end
end
