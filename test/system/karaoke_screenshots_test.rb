require "application_system_test_case"
require_relative "karaoke_queue_test"

# TEMPORARY: screenshots for eyeballing the queue UI. Delete before committing.
class KaraokeScreenshotsTest < ApplicationSystemTestCase
  setup do
    KaraokeQueueItem.delete_all
    [
      [ "SYSQUEUE001", "Dancing Queen", "ABBA", "Sam" ],
      [ "SYSQUEUE002", "Bohemian Rhapsody", "Queen", "Lucas" ],
      [ "SYSQUEUE003", "Don't Stop Believin'", "Journey", nil ]
    ].each_with_index do |(isrc, title, artist, by), index|
      KaraokeQueueItem.create!(song_isrc: isrc, title: title, artist: artist, image_url: "/icon.png", added_by: by, position: index + 1)
    end
  end

  teardown { KaraokeQueueItem.delete_all }

  test "screenshot the karaoke screen" do
    visit root_path
    assert_selector ".karaoke-queue__item", count: 3
    page.save_screenshot("tmp/screenshots/shot_screen.png")
  end

  test "screenshot the phone remote" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit karaoke_remote_path(code: KaraokeRemote.code)
    assert_selector ".karaoke-remote__queue-item", count: 3
    page.save_screenshot("tmp/screenshots/shot_remote.png")

    visit karaoke_remote_path
    assert_selector ".karaoke-remote__lock"
    page.save_screenshot("tmp/screenshots/shot_remote_lock.png")
  end
end
