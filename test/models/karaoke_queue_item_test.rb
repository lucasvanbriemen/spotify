require "test_helper"

# Reordering is the part of the queue with real invariants: positions are
# deliberately sparse (next_position counts off the all-time maximum) and
# promote! can tie two rows, so a naive swap has several ways to silently do
# nothing. These tests pin the cases that actually occur during an evening.
class KaraokeQueueItemTest < ActiveSupport::TestCase
  def setup
    KaraokeQueueItem.delete_all
  end

  def enqueue(title)
    KaraokeQueueItem.enqueue(song_isrc: "ISRC#{title}", title: title, artist: "Artist")
  end

  def order
    KaraokeQueueItem.waiting.map(&:title)
  end

  test "move down swaps a row with the one after it" do
    %w[a b c].each { |title| enqueue(title) }

    assert enqueue("a").move!("down")
    assert_equal %w[b a c], order
  end

  test "move up swaps a row with the one before it" do
    %w[a b c].each { |title| enqueue(title) }

    assert enqueue("c").move!("up")
    assert_equal %w[a c b], order
  end

  test "moving past either end is a no-op rather than an error" do
    %w[a b].each { |title| enqueue(title) }

    assert_not enqueue("a").move!("up")
    assert_not enqueue("b").move!("down")
    assert_equal %w[a b], order
  end

  # The case that made a swap unreliable before resequence! existed: promote!
  # subtracts from the minimum, so promoting the row that is already first
  # leaves nothing tied — but promoting the second row twice, or promoting
  # after rows have been played, leaves gaps a swap has to survive.
  test "reordering survives the sparse positions promote! and next_position leave" do
    %w[a b c].each { |title| enqueue(title) }
    enqueue("c").promote!
    assert_equal %w[c a b], order

    assert enqueue("c").move!("down")
    assert_equal %w[a c b], order

    assert enqueue("b").move!("up")
    assert_equal %w[a b c], order
  end

  test "resequence! renumbers the waiting list to 1..n without reordering it" do
    %w[a b c].each { |title| enqueue(title) }
    enqueue("c").promote!

    KaraokeQueueItem.resequence!

    assert_equal %w[c a b], order
    assert_equal [ 1, 2, 3 ], KaraokeQueueItem.waiting.map(&:position)
  end

  # Two rows sharing a position is the state that made a swap a no-op: the
  # order between them falls back to id, which is exactly what a move is meant
  # to override.
  test "reordering works even when two rows start out tied on position" do
    a = enqueue("a")
    b = enqueue("b")
    b.update_columns(position: a.position)

    assert b.move!("up")
    assert_equal %w[b a], order
  end

  test "shuffling deals the waiting list out again without losing or duplicating a row" do
    %w[a b c d e].each { |title| enqueue(title) }

    KaraokeQueueItem.shuffle!

    assert_equal %w[a b c d e], order.sort
    assert_equal [ 1, 2, 3, 4, 5 ], KaraokeQueueItem.waiting.map(&:position)
  end

  test "shuffling leaves the song on stage and the ones already sung alone" do
    %w[a b c].each { |title| enqueue(title) }
    playing = enqueue("a")
    playing.start!
    sung = enqueue("b")
    sung.finish!

    KaraokeQueueItem.shuffle!

    assert_equal %w[c], order
    assert_equal "playing", playing.reload.status
    assert_equal "done", sung.reload.status
  end

  test "a played row keeps its position out of the waiting list's numbering" do
    %w[a b c].each { |title| enqueue(title) }
    enqueue("a").finish!

    KaraokeQueueItem.resequence!

    assert_equal %w[b c], order
    assert_equal [ 1, 2 ], KaraokeQueueItem.waiting.map(&:position)
  end
end
