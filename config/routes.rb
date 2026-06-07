Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # JSON API used by the iOS app (paths mirror the old Laravel routes —
  # https://music.ltvb.nl/api/...).
  scope "api" do
    get "search", to: "spotify#search", as: :search
    get "get-mp3/:isrc", to: "spotify#get_mp3", as: :get_mp3, constraints: { isrc: /[^\/]+/ }
    get "song/:isrc/lyrics", to: "spotify#lyrics", as: :song_lyrics, constraints: { isrc: /[^\/]+/ }

    get "playlists", to: "playlists#index", as: :playlists
    get "playlist/:id", to: "playlists#show", as: :playlist
    post "playlist/:id/songs", to: "playlists#add_song", as: :playlist_songs

    post "plays", to: "stats#store_play", as: :plays
    get "stats", to: "stats#index", as: :stats
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
