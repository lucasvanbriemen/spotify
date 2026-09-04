require "test_helper"

# Authentication talks to the live login service, so it is replaced here. The
# flag is what tells the two clients apart: the karaoke screen is a logged-in
# page, a phone on /karaoke/remote is not and carries tonight's join code
# instead.
module KaraokeQueueTestLogin
  mattr_accessor :logged_in, default: true

  def require_login
    return @current_account = { "name" => "Tester" } if KaraokeQueueTestLogin.logged_in

    redirect_to Authentication::LOGIN_URL, allow_other_host: true
  end
end
KaraokeQueueController.prepend(KaraokeQueueTestLogin)

class KaraokeQueueControllerTest < ActionDispatch::IntegrationTest
  ISRC = "TESTQUEUE001".freeze
  OTHER_ISRC = "TESTQUEUE002".freeze

  setup do
    KaraokeQueueItem.delete_all
  end

  teardown do
    KaraokeQueueTestLogin.logged_in = true
    KaraokeQueueItem.delete_all
  end

  test "queueing a song answers with the whole queue and starts separating it" do
    assert_enqueued_with(job: PrepareKaraokeJob, args: [ ISRC ]) do
      add_song(ISRC, title: "First")
    end
    assert_response :created

    payload = JSON.parse(response.body)
    assert_nil payload["now_playing"]
    assert_equal [ "First" ], payload["items"].map { |item| item["title"] }
    assert_equal "Lucas", payload["items"].first["added_by"]
  end

  test "queueing a song that is already waiting is a double tap, not a second turn" do
    add_song(ISRC)
    add_song(ISRC)

    assert_equal 1, KaraokeQueueItem.waiting.count
  end

  test "an unusable isrc never reaches the queue" do
    post "/api/karaoke/queue", params: { isrc: "not valid", title: "X", artist: "Y" }, as: :json
    assert_response :bad_request
    assert_equal 0, KaraokeQueueItem.count
  end

  test "a song without a title is unprocessable" do
    post "/api/karaoke/queue", params: { isrc: ISRC, artist: "Y" }, as: :json
    assert_response :unprocessable_entity
  end

  test "claiming a song moves it out of the queue and onto the stage" do
    add_song(ISRC, title: "First")
    add_song(OTHER_ISRC, title: "Second")
    first = KaraokeQueueItem.waiting.first

    patch "/api/karaoke/queue/#{first.id}", params: { status: "playing" }, as: :json
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "First", payload["now_playing"]["title"]
    assert_equal [ "Second" ], payload["items"].map { |item| item["title"] }

    patch "/api/karaoke/queue/#{first.id}", params: { status: "done" }, as: :json
    assert_nil JSON.parse(response.body)["now_playing"]
  end

  test "a second claim releases the song the last one left on stage" do
    add_song(ISRC)
    add_song(OTHER_ISRC)
    first, second = KaraokeQueueItem.waiting.to_a

    patch "/api/karaoke/queue/#{first.id}", params: { status: "playing" }, as: :json
    patch "/api/karaoke/queue/#{second.id}", params: { status: "playing" }, as: :json
    assert_response :success

    assert_equal "done", first.reload.status
    assert_equal second.id, JSON.parse(response.body)["now_playing"]["id"]
  end

  test "promoting a song puts it at the front" do
    add_song(ISRC, title: "First")
    add_song(OTHER_ISRC, title: "Second")
    last = KaraokeQueueItem.waiting.last

    post "/api/karaoke/queue/#{last.id}/promote"
    assert_response :success

    assert_equal [ "Second", "First" ], JSON.parse(response.body)["items"].map { |item| item["title"] }
  end

  # The order comes back from the server rather than being dealt by whichever
  # client pressed the button: every phone in the room has to agree on it.
  test "shuffling answers with the reordered queue" do
    titles = %w[First Second Third Fourth Fifth]
    titles.each_with_index { |title, index| add_song("TESTQUEUE00#{index}", title: title) }

    post "/api/karaoke/queue/shuffle"
    assert_response :success

    shuffled = JSON.parse(response.body)["items"].map { |item| item["title"] }
    assert_equal titles.sort, shuffled.sort
    assert_equal shuffled, KaraokeQueueItem.waiting.map(&:title)
  end

  test "clearing takes out what is waiting and leaves what has been sung" do
    add_song(ISRC)
    add_song(OTHER_ISRC)
    sung = KaraokeQueueItem.waiting.first
    sung.finish!

    delete "/api/karaoke/queue"
    assert_response :success

    assert_equal [], JSON.parse(response.body)["items"]
    assert_equal [ sung.id ], KaraokeQueueItem.pluck(:id)
  end

  test "a phone holding tonight's code can use the queue without an account" do
    KaraokeQueueTestLogin.logged_in = false

    get "/api/karaoke/queue?code=#{KaraokeRemote.code}"
    assert_response :success

    post "/api/karaoke/queue",
      params: { isrc: ISRC, title: "From a phone", artist: "Guest", added_by: "Sam", code: KaraokeRemote.code },
      as: :json
    assert_response :created
    assert_equal "Sam", KaraokeQueueItem.waiting.first.added_by
  end

  test "without the code there is nothing here but the login page" do
    KaraokeQueueTestLogin.logged_in = false

    get "/api/karaoke/queue"
    assert_redirected_to Authentication::LOGIN_URL

    get "/api/karaoke/queue?code=WRONG"
    assert_redirected_to Authentication::LOGIN_URL
  end

  private

  def add_song(isrc, title: "Test Song")
    post "/api/karaoke/queue",
      params: { isrc: isrc, title: title, artist: "Tester", image_url: "https://example.com/art.jpg", added_by: "Lucas" },
      as: :json
  end
end

class KaraokeRemoteTest < ActiveSupport::TestCase
  test "the code is stable through the day and survives midnight" do
    assert_equal KaraokeRemote.code, KaraokeRemote.code
    assert_equal KaraokeRemote::LENGTH, KaraokeRemote.code.length

    assert KaraokeRemote.valid?(KaraokeRemote.code.downcase)
    # A party running past midnight must not lock every phone in the room out.
    assert KaraokeRemote.valid?(KaraokeRemote.code(Date.yesterday))
    assert_not KaraokeRemote.valid?(KaraokeRemote.code(2.days.ago.to_date))
    assert_not KaraokeRemote.valid?("")
    assert_not KaraokeRemote.valid?(nil)
  end
end
