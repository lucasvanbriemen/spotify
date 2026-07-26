require "test_helper"

class StationQueueBuilderTest < ActiveSupport::TestCase
  setup do
    # The test cache store is :null_store; talk cooldowns need a real one.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @station = Station.find("genre-rock")
  end

  teardown do
    Rails.cache = @original_cache
    FileUtils.rm_f(@news_file) if @news_file
  end

  test "a chunk never repeats a song" do
    items = build(count: 10)
    song_isrcs = items.select { |item| item[:kind] == "song" }.map { |item| item[:isrc] }

    assert_equal song_isrcs.uniq, song_isrcs
  end

  test "recently played songs are excluded" do
    played = songs(:rock_0)
    Play.create!(song_isrc: played.isrc, seconds_played: 120)

    items = build(count: 15)

    assert_not_includes items.map { |item| item[:isrc] }, played.isrc
  end

  test "the recency exclusion is dropped when it would empty the pool" do
    Song.where(genre: "Rock").pluck(:isrc).each do |isrc|
      Play.create!(song_isrc: isrc, seconds_played: 120)
    end

    items = build(count: 5)

    assert_operator items.count { |item| item[:kind] == "song" }, :>=, 5
  end

  test "every item ships the fields the app force-unwraps" do
    items = build(count: 10)

    assert items.any?
    items.each do |item|
      assert item[:isrc].present?, "isrc missing in #{item.inspect}"
      assert item[:title].present?, "title missing in #{item.inspect}"
      assert item[:artist].present?, "artist missing in #{item.inspect}"
      assert item[:image_url].present?, "image_url missing in #{item.inspect}"
      assert item[:duration].is_a?(Integer), "duration not an integer in #{item.inspect}"
      assert %w[song talk].include?(item[:kind])
    end
  end

  test "talk ids satisfy the get-mp3 gate" do
    items = build(count: 10)
    talk_ids = items.select { |item| item[:kind] == "talk" }.map { |item| item[:isrc] }

    assert talk_ids.any?, "expected the chunk to mint talk segments"
    talk_ids.each do |id|
      assert_match(/\A[a-zA-Z0-9-]+\z/, id)
      assert_match TalkSegment::ID_PATTERN, id
    end
  end

  test "a fresh ready bulletin airs first, then respects the cooldown" do
    create_ready_news

    first_chunk = build(count: 5)
    assert_equal "news", first_chunk.first[:talk_kind]

    second_chunk = build(count: 5)
    assert_not second_chunk.any? { |item| item[:talk_kind] == "news" },
      "the news cooldown should keep the bulletin out of back-to-back chunks"
  end

  test "a stale bulletin does not air" do
    create_ready_news(created_at: 2.hours.ago)

    items = build(count: 5)

    assert_not items.any? { |item| item[:talk_kind] == "news" }
  end

  test "a bulletin without its audio file does not air" do
    TalkSegment.create!(
      id: "talk-news-nl-fileless", kind: "news", language: "nl",
      transcript: "x", duration: 60, status: "ready", expires_at: 1.day.from_now
    )

    items = build(count: 5)

    assert_not items.any? { |item| item[:talk_kind] == "news" }
  end

  test "the TTS circuit breaker stops new talk from being minted" do
    Rails.cache.write(Tts::Client::BREAKER_KEY, true)

    items = build(count: 10)

    assert items.all? { |item| item[:kind] == "song" }
    assert_equal 0, TalkSegment.count
  end

  test "any talk failure degrades to a songs-only chunk" do
    TalkSegment.stub(:find_or_create_by!, ->(*) { raise "boom" }) do
      items = build(count: 5)

      assert_equal 5, items.size
      assert items.all? { |item| item[:kind] == "song" }
    end
  end

  private

  def build(count:)
    StationQueueBuilder.new(@station, count: count, base_url: "http://test.host").build
  end

  def create_ready_news(created_at: Time.current)
    segment = TalkSegment.create!(
      id: "talk-news-nl-testbulletin", kind: "news", language: "nl",
      transcript: "Het nieuws.", duration: 60, status: "ready",
      expires_at: 1.day.from_now, created_at: created_at
    )
    @news_file = segment.audio_path
    FileUtils.mkdir_p(File.dirname(@news_file))
    File.binwrite(@news_file, "mp3")
    segment
  end
end
