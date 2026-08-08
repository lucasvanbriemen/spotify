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
      lines = TalkScripts.build(segment)
      clips = Tts::Client.synthesize_lines(
        lines: lines,
        language: segment.language,
        kind: segment.kind
      )
      transcript = transcript_for(lines)
      path = write_normalized(segment.id, clips)
      segment.update!(transcript: transcript, duration: measure_duration(path, transcript), status: "ready")
    end

    # TTS speech comes out quieter than mastered music; a single loudnorm pass
    # brings it to streaming loudness so segments don't whisper between songs.
    # Multi-host clips are joined with a short studio pause before that pass.
    # Without local ffmpeg (dev machines), concatenated MP3 frames are used.
    def write_normalized(id, clips)
      FileUtils.mkdir_p(SongCache::AUDIO_DIR)
      out = SongCache.path(id)
      ffmpeg = ExecutablePath.resolve("ffmpeg")

      unless ffmpeg.executable?
        File.binwrite(out, clips.join)
        return out
      end

      tmp_dir = Dir.mktmpdir("talk-#{id}-", Rails.root.join("tmp"))
      inputs = clips.each_with_index.flat_map do |bytes, index|
        path = File.join(tmp_dir, "#{index}.mp3")
        File.binwrite(path, bytes)
        [ "-i", path ]
      end
      filters = clips.each_index.map do |index|
        "[#{index}:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a#{index}]"
      end

      if clips.one?
        filters << "[a0]loudnorm=I=-14:TP=-1.5:LRA=11[out]"
      else
        pauses = (clips.size - 1).times.map do |index|
          filters << "anullsrc=r=44100:cl=stereo,atrim=duration=0.22[p#{index}]"
          "[p#{index}]"
        end
        sequence = clips.each_index.flat_map do |index|
          parts = [ "[a#{index}]" ]
          parts << pauses[index] if pauses[index]
          parts
        end.join
        filters << "#{sequence}concat=n=#{clips.size * 2 - 1}:v=0:a=1," \
          "loudnorm=I=-14:TP=-1.5:LRA=11[out]"
      end

      ok = system(
        ffmpeg.to_s, "-y", *inputs,
        "-filter_complex", filters.join(";"),
        "-map", "[out]", "-ar", "44100", "-b:a", "128k",
        out.to_s, out: File::NULL, err: File::NULL
      )
      raise Tts::Error, "ffmpeg normalize failed" unless ok && out.file?

      out
    ensure
      FileUtils.remove_entry(tmp_dir) if tmp_dir && File.directory?(tmp_dir)
    end

    def transcript_for(lines)
      return lines.first.fetch(:text) if lines.one?

      labels = { "host" => "Host", "cohost" => "Co-host" }
      lines.map { |line| "#{labels.fetch(line.fetch(:speaker), 'Host')}: #{line.fetch(:text)}" }.join("\n\n")
    end

    # There is no ffprobe on the server: parse "Duration: 00:01:02.34" from
    # `ffmpeg -i` stderr, falling back to a speech-rate estimate.
    def measure_duration(path, script)
      ffmpeg = ExecutablePath.resolve("ffmpeg")
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
