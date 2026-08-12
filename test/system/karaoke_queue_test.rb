require "application_system_test_case"

# The queue, end to end in a real browser: the panel on the karaoke screen and
# the phone remote that fills it. Authentication talks to the live login
# service, so the screen's half runs with it stubbed out — the remote's half
# does not, because a guest holding the code is exactly what it has to work
# for.
module KaraokeSystemLogin
  def require_login
    @current_account = { "name" => "Tester" }
  end
end
KaraokeController.prepend(KaraokeSystemLogin)
KaraokeQueueController.prepend(KaraokeSystemLogin)
KaraokeScoresController.prepend(KaraokeSystemLogin)

class KaraokeQueueTest < ApplicationSystemTestCase
  setup do
    KaraokeQueueItem.delete_all
    KaraokeQueueItem.create!(
      song_isrc: "SYSQUEUE001", title: "Dancing Queen", artist: "ABBA",
      image_url: "/icon.png", added_by: "Sam", position: 1
    )
    KaraokeQueueItem.create!(
      song_isrc: "SYSQUEUE002", title: "Bohemian Rhapsody", artist: "Queen",
      image_url: "/icon.png", added_by: "Lucas", position: 2
    )
  end

  teardown do
    KaraokeQueueItem.delete_all
  end

  test "the karaoke screen lists what the room has queued" do
    visit root_path

    assert_selector ".karaoke-queue__item", count: 2
    assert_text "Dancing Queen"
    assert_text "Sam"
    # The invite is the whole point of the panel: without a code on screen,
    # nobody's phone can reach it.
    assert_text KaraokeRemote.code
  end

  test "moving a song to the front reorders the queue for everyone" do
    visit root_path

    within(".karaoke-queue__item", text: "Bohemian Rhapsody") { click_button "↑" }

    assert_selector ".karaoke-queue__item:first-child", text: "Bohemian Rhapsody"
    assert_equal "SYSQUEUE002", KaraokeQueueItem.waiting.first.song_isrc
  end

  test "removing a song takes it out of the panel" do
    visit root_path

    within(".karaoke-queue__item", text: "Dancing Queen") { find("button[aria-label='Remove from queue']").click }

    assert_selector ".karaoke-queue__item", count: 1
    assert_no_text "Dancing Queen"
  end

  test "a phone without the code is asked for it" do
    visit karaoke_remote_path

    assert_selector ".karaoke-remote__lock"
    assert_selector "input[aria-label='Join code']"
  end

  test "a phone holding the code sees the queue and can drop its own song" do
    visit karaoke_remote_path(code: KaraokeRemote.code)

    assert_selector ".karaoke-remote__queue-item", count: 2
    assert_text "Dancing Queen"

    fill_in "Your name", with: "Sam"
    # Only your own turn is yours to cancel, so the button appears with the
    # name that put the song there.
    within(".karaoke-remote__queue-item", text: "Dancing Queen") { find("button[aria-label='Remove Dancing Queen']").click }

    assert_selector ".karaoke-remote__queue-item", count: 1
  end
end
