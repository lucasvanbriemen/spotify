# Renders one talk segment (intro/weather) in the background. Enqueued by the
# queue builder and the prepare endpoint; safe to enqueue twice for the same
# id thanks to TalkAudio's per-id lock and rendered? check.
class GenerateTalkSegmentJob < ApplicationJob
  queue_as :default

  def perform(id)
    TalkAudio.ensure_rendered(id)
  end
end
