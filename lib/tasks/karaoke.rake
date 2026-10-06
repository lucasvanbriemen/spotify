namespace :karaoke do
  desc "Recreate Song rows for cached/prepared ISRC tracks lost to the YouTube rekey, and move their scores back (see KaraokeLibraryRestore)"
  task restore_song_rows: :environment do
    KaraokeLibraryRestore.new.run(only_prepared: ENV["ONLY_PREPARED"].present?)
  end
end
