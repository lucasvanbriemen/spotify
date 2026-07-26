require "test_helper"

class SpotifyControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "get-mp3 for a talk id never touches the song download path" do
    SongCache.stub(:ensure_cached, ->(*) { raise "yt-dlp path must not run for talk ids" }) do
      TalkAudio.stub(:ensure_rendered, false) do
        get "/api/get-mp3/talk-news-nl-2026072608", headers: AUTH_HEADERS
      end
    end

    assert_response :not_found
  end

  test "get-mp3 serves rendered talk audio" do
    segment = create_segment("talk-news-nl-servetest", transcript: "Het nieuws.")
    File.binwrite(segment.audio_path, "mp3-bytes")

    get "/api/get-mp3/#{segment.id}", headers: AUTH_HEADERS

    assert_response :success
    assert_equal "mp3-bytes", response.body
  ensure
    FileUtils.rm_f(segment.audio_path)
  end

  test "prepare enqueues a talk render for pending segments" do
    segment = create_segment("talk-intro-preparetest01", status: "pending")

    assert_enqueued_with(job: GenerateTalkSegmentJob, args: [ segment.id ]) do
      post "/api/get-mp3/#{segment.id}/prepare", headers: AUTH_HEADERS
    end
    assert_response :accepted
  end

  test "lyrics for a talk id return the transcript with coarse synced lines" do
    segment = create_segment(
      "talk-news-nl-lyricstest",
      transcript: "Eerste zin. Tweede zin. Derde zin.", duration: 30
    )

    get "/api/song/#{segment.id}/lyrics", headers: AUTH_HEADERS

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal segment.transcript, body["plainLyrics"]
    assert_includes body["syncedLyrics"], "[00:00.00] Eerste zin."
    assert_includes body["syncedLyrics"], "[00:10.00] Tweede zin."
  end

  test "lyrics 404 for a talk id without a transcript" do
    create_segment("talk-intro-notranscript1", transcript: nil)

    get "/api/song/talk-intro-notranscript1/lyrics", headers: AUTH_HEADERS

    assert_response :not_found
  end

  private

  def create_segment(id, transcript: "Tekst.", duration: 20, status: "ready")
    TalkSegment.create!(
      id: id, kind: id.split("-")[1], language: "nl",
      transcript: transcript, duration: duration, status: status,
      expires_at: 1.day.from_now
    )
  end
end
