# Resolves a bin/<name> executable across platforms: Windows ships .exe
# binaries (bin/yt-dlp.exe, bin/ffmpeg.exe) since the bare name isn't
# directly runnable there, while Unix hosts run the bare bin/<name> file.
module ExecutablePath
  def self.resolve(name)
    windows_path = Rails.root.join("bin", "#{name}.exe")
    windows_path.exist? ? windows_path : Rails.root.join("bin", name)
  end
end
