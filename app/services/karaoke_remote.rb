# The join code a phone needs to reach the queue endpoints without an account.
#
# Every other page in this app is behind the login service, which is exactly
# wrong for the remote: the people who want to queue a song are guests in the
# room, and guests do not have logins. A code shown on the karaoke screen is
# the credential instead — knowing it lets you add and remove songs, and
# nothing else.
#
# It is derived rather than stored: same code in every process, no cache or
# table to keep in sync, and it rotates on its own each day.
class KaraokeRemote
  # No I, O, 0 or 1 — those are the characters people mistype reading a code
  # off a TV from across the room.
  ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze
  LENGTH = 4

  class << self
    def code(day = Date.current)
      digest = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "karaoke-remote/#{day}")
      digest.unpack("C*").first(LENGTH).map { |byte| ALPHABET[byte % ALPHABET.size] }.join
    end

    def valid?(candidate)
      candidate = candidate.to_s.upcase
      return false if candidate.blank?

      # Yesterday's code keeps working so a party running past midnight doesn't
      # lock every phone in the room out at 00:00.
      [ Date.current, Date.yesterday ].any? do |day|
        ActiveSupport::SecurityUtils.secure_compare(candidate, code(day))
      end
    end
  end
end
