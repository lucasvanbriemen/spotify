Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # JSON API used by the iOS app (paths mirror the old Laravel routes —
  # https://music.ltvb.nl/api/...).
  scope "api" do
    get "search", to: "spotify#search", as: :search
    get "karaoke-search", to: "spotify#karaoke_search", as: :karaoke_search
    get "get-mp3/:isrc", to: "spotify#get_mp3", as: :get_mp3, constraints: { isrc: /[^\/]+/ }
    post "get-mp3/:isrc/prepare", to: "spotify#prepare", as: :prepare_mp3, constraints: { isrc: /[^\/]+/ }
    get "song/:isrc/lyrics", to: "spotify#lyrics", as: :song_lyrics, constraints: { isrc: /[^\/]+/ }

    scope "karaoke/:isrc", constraints: { isrc: /[^\/]+/ } do
      post "prepare", to: "karaoke_tracks#prepare", as: :karaoke_prepare
      get "status", to: "karaoke_tracks#status", as: :karaoke_status
      get "instrumental", to: "karaoke_tracks#instrumental", as: :karaoke_instrumental
      get "vocals", to: "karaoke_tracks#vocals", as: :karaoke_vocals
      get "pitch", to: "karaoke_tracks#pitch", as: :karaoke_pitch
      get "notes", to: "karaoke_tracks#notes", as: :karaoke_notes
      get "words", to: "karaoke_tracks#words", as: :karaoke_words
      get "scores", to: "karaoke_scores#index", as: :karaoke_scores
      post "scores", to: "karaoke_scores#create", as: :karaoke_score
    end

    get "karaoke-history", to: "karaoke_scores#history", as: :karaoke_history

    get "playlists", to: "playlists#index", as: :playlists
    get "playlist/:id", to: "playlists#show", as: :playlist
    post "playlist/:id/prepare", to: "playlists#prepare", as: :playlist_prepare
    post "playlist/:id/songs", to: "playlists#add_song", as: :playlist_songs

    get "stations", to: "stations#index", as: :stations
    get "station/:id/queue", to: "stations#queue", as: :station_queue, constraints: { id: /[a-z0-9-]+/ }

    post "plays", to: "stats#store_play", as: :plays
    get "stats", to: "stats#index", as: :stats
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "karaoke#index"
end
