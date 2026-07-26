# Talk audio is disposable by design (bulletins go stale within the hour), so
# unlike the song cache it must not accumulate: sweep expired segments and any
# orphaned talk files daily.
class CleanupTalkSegmentsJob < ApplicationJob
  queue_as :default

  def perform
    TalkSegment.where(expires_at: ...Time.current).find_each do |segment|
      FileUtils.rm_f(segment.audio_path)
      FileUtils.rm_f(SongCache::AUDIO_DIR.join("#{segment.id}.lock"))
      segment.destroy!
    end

    # Orphan sweep: talk audio whose row is gone (e.g. a crash mid-render).
    Dir.glob(SongCache::AUDIO_DIR.join("talk-*.mp3")).each do |file|
      FileUtils.rm_f(file) unless TalkSegment.exists?(id: File.basename(file, ".mp3"))
    end
  end
end
