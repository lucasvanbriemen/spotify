# The party queue: what everyone has lined up to sing. Rows are added by the
# karaoke screen itself and by phones on /karaoke/remote; the screen claims
# them in order, marking each one playing and then done.
class KaraokeQueueItem < ApplicationRecord
  # No belongs_to :song, unlike KaraokeScore. A songs row only exists once a
  # track has been cached (see SongCache.ensure_cached), and the whole point of
  # a queue is to line up songs nobody has played yet — so what the screen has
  # to draw is copied onto the row instead.
  STATUSES = %w[pending playing done].freeze

  # Same format check as the karaoke API's ValidatesIsrc: it is also what keeps
  # the value safe to join onto a cached-file path downstream.
  SONG_ISRC_FORMAT = /\A[a-zA-Z0-9-]+\z/

  # A "playing" row is only trusted for this long: closing the browser mid-song
  # leaves one behind, and nothing else would ever clear it.
  PLAYING_TTL = 2.hours
  # Finished rows are kept only long enough to still be interesting on a phone
  # that was looking at the queue when the song ended.
  KEEP_PLAYED_FOR = 1.day

  normalizes :added_by, with: ->(name) { name.to_s.strip.presence }
  normalizes :title, :artist, with: ->(value) { value.to_s.strip }

  validates :song_isrc, presence: true, format: { with: SONG_ISRC_FORMAT }
  validates :title, :artist, presence: true
  validates :added_by, length: { maximum: 50 }
  validates :status, inclusion: { in: STATUSES }

  scope :waiting, -> { where(status: "pending").order(:position, :id) }
  scope :played, -> { where(status: "done") }

  class << self
    # Adding a song already waiting is a double tap, not a request to sing it
    # twice — hand back the row that is already in the queue.
    def enqueue(attributes)
      existing = waiting.find_by(song_isrc: attributes[:song_isrc])
      return existing if existing

      create(attributes.merge(status: "pending", position: next_position))
    end

    # The song on stage right now, if the screen is still alive to have put it
    # there.
    def now_playing
      where(status: "playing").where(updated_at: PLAYING_TTL.ago..).order(updated_at: :desc).first
    end

    # Positions are handed out off the all-time maximum rather than the
    # waiting rows' — reusing a finished row's number would tie two items for
    # the same spot in the queue.
    def next_position
      (maximum(:position) || 0) + 1
    end

    def prune_played
      played.where(played_at: ...KEEP_PLAYED_FOR.ago).delete_all
    end

    # Renumbers the waiting list to 1..n, so a swap can mean exactly one place.
    #
    # Positions drift by design: next_position counts off the all-time maximum
    # so a finished row's number is never reused, and promote! goes below the
    # current minimum. Gaps are therefore normal — and promoting the row that
    # was already first leaves two rows tied, which would make a swap silently
    # do nothing at all.
    #
    # update_columns, not update!: a position is bookkeeping. Touching
    # updated_at here would look like activity to a phone watching the queue,
    # and ages rows against the window now_playing trusts.
    def resequence!
      transaction do
        waiting.each_with_index do |row, index|
          row.update_columns(position: index + 1) unless row.position == index + 1
        end
      end
    end
  end

  # Only one song can be on stage, so claiming this one releases whatever the
  # last screen left behind.
  def start!
    self.class.where(status: "playing").where.not(id: id).update_all(status: "done", played_at: Time.current)
    update!(status: "playing", played_at: Time.current)
  end

  def finish!
    update!(status: "done", played_at: played_at || Time.current)
  end

  # Straight to the front of the queue. Sharing the minimum with the current
  # first item would leave the tie broken by id, which is the order this is
  # meant to override.
  def promote!
    update!(position: (self.class.waiting.minimum(:position) || 1) - 1)
  end

  # One step up or down the waiting list, for the phone's ▲/▼ buttons.
  # Returns false at the ends rather than raising: tapping ▲ on the first row
  # is a miss, not an error.
  def move!(direction)
    self.class.resequence!

    rows = self.class.waiting.to_a
    from = rows.index { |row| row.id == id }
    return false unless from

    to = direction.to_s == "up" ? from - 1 : from + 1
    return false unless to.between?(0, rows.size - 1)

    # resequence! just made every position exactly its index + 1, so the swap
    # is the two indexes rather than a pair of read-back values.
    self.class.transaction do
      rows[from].update_columns(position: to + 1)
      rows[to].update_columns(position: from + 1)
    end
    true
  end
end
