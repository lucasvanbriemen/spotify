# Renders a TalkSegment to MP3 in storage/audio (script -> TTS -> loudness
# normalize), mirroring SongCache: same directory (so X-Sendfile serving works
# unchanged) and the same per-id flock so a just-in-time render in get-mp3 and
# a background job never render the same segment twice.
class TalkAudio
  class << self
    def rendered?(id)
      SongCache.path(id).file?
    end

    # Returns true when the segment's audio is on disk. Never touches
    # yt-dlp/Deezer: talk audio is generated, not downloaded.
    def ensure_rendered(id)
      return true if rendered?(id)

      segment = TalkSegment.find_by(id: id)
      return false unless segment && segment.status != "failed"

      with_lock(id) do
        next true if rendered?(id)

        render(segment)
        rendered?(id)
      end
    rescue Openai::Client::Error, Tts::Error, Weather::Error => e
      segment&.update(status: "failed")
      Rails.logger.warn("talk render failed for #{id}: #{e.message}")
      false
    end

    private

    # Same discipline as SongCache.with_lock.
    def with_lock(id)
      FileUtils.mkdir_p(SongCache::AUDIO_DIR)
      File.open(SongCache::AUDIO_DIR.join("#{id}.lock"), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def render(segment)
      script = TalkScripts.build(segment)
      audio = Tts::Client.synthesize(
        text: script,
        language: segment.language,
        kind: segment.kind
      )
      path = write_normalized(segment.id, audio)
      segment.update!(transcript: script, duration: measure_duration(path, script), status: "ready")
    end

    # TTS speech comes out quieter than mastered music; a single loudnorm pass
    # brings it to streaming loudness so segments don't whisper between songs.
    # Without a local ffmpeg (dev machines) the raw TTS MP3 is used as-is.
    def write_normalized(id, mp3_bytes)
      FileUtils.mkdir_p(SongCache::AUDIO_DIR)
      out = SongCache.path(id)
      ffmpeg = Rails.root.join("bin/ffmpeg")

      unless ffmpeg.executable?
        File.binwrite(out, mp3_bytes)
        return out
      end

      tmp = Rails.root.join("tmp", "talk-#{id}.mp3")
      File.binwrite(tmp, mp3_bytes)
      ok = system(
        ffmpeg.to_s, "-y", "-i", tmp.to_s,
        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11",
        "-ar", "44100", "-b:a", "128k",
        out.to_s,
        out: File::NULL, err: File::NULL
      )
      raise Tts::Error, "ffmpeg normalize failed" unless ok && out.file?

      out
    ensure
      FileUtils.rm_f(tmp) if tmp
    end

    # There is no ffprobe on the server: parse "Duration: 00:01:02.34" from
    # `ffmpeg -i` stderr, falling back to a speech-rate estimate.
    def measure_duration(path, script)
      ffmpeg = Rails.root.join("bin/ffmpeg")
      if ffmpeg.executable?
        output = `#{Shellwords.escape(ffmpeg.to_s)} -i #{Shellwords.escape(path.to_s)} 2>&1`
        if output =~ /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/
          return (::Regexp.last_match(1).to_i * 3600 +
                  ::Regexp.last_match(2).to_i * 60 +
                  ::Regexp.last_match(3).to_f).ceil
        end
      end

      (script.split.size / 2.5).ceil
    end
  end
end
