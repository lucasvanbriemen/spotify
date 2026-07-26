# Fills the song metadata columns (genre/release_year/bpm/deezer_rank) that
# station building needs. Deezer is the source: tracks are keyed exactly by
# ISRC there, and both Song write sites already hold a Deezer track payload.
class SongEnrichment
  class << self
    # Pure mapping from a Deezer track payload to song attributes. Deezer uses
    # 0 for unknown bpm/rank and "0000-00-00" for unknown release dates.
    def attributes_from_track(details)
      {
        bpm: positive_or_nil(details["bpm"])&.to_f,
        release_year: year_from(details["release_date"]),
        deezer_rank: positive_or_nil(details["rank"])&.to_i
      }.compact
    end

    # Genre lives on the album, not the track, so it costs one extra Deezer
    # call. Returns nil when the album is unknown, the call fails, or the
    # genre is Deezer's catch-all "All".
    def genre_for(album_id)
      return nil if album_id.blank?

      name = Deezer::Client.album_details(album_id).dig("genres", "data", 0, "name")
      name.presence unless name == "All"
    rescue Deezer::Client::Error
      nil
    end

    # Network path used by the backfill. Sets enriched_at even when Deezer
    # fails so the backfill never loops on a dead ISRC.
    def enrich!(song)
      details = Deezer::Client.track_details(song.isrc)
      song.update!(
        **attributes_from_track(details),
        genre: genre_for(details.dig("album", "id")),
        enriched_at: Time.current
      )
    rescue Deezer::Client::Error
      song.update!(enriched_at: Time.current)
    end

    private

    def positive_or_nil(value)
      value if value.to_f.positive?
    end

    def year_from(release_date)
      year = release_date.to_s[0, 4].to_i
      year if year > 1900
    end
  end
end
