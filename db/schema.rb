# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_26_000003) do
  create_table "cache", primary_key: "key", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.text "value", size: :medium, null: false
    t.integer "expiration", null: false
    t.index ["expiration"], name: "cache_expiration_index"
  end

  create_table "cache_locks", primary_key: "key", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "owner", null: false
    t.integer "expiration", null: false
    t.index ["expiration"], name: "cache_locks_expiration_index"
  end

  create_table "failed_jobs", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "uuid", null: false
    t.text "connection", null: false
    t.text "queue", null: false
    t.text "payload", size: :long, null: false
    t.text "exception", size: :long, null: false
    t.timestamp "failed_at", default: -> { "current_timestamp()" }, null: false
    t.index ["uuid"], name: "failed_jobs_uuid_unique", unique: true
  end

  create_table "job_batches", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "total_jobs", null: false
    t.integer "pending_jobs", null: false
    t.integer "failed_jobs", null: false
    t.text "failed_job_ids", size: :long, null: false
    t.text "options", size: :medium
    t.integer "cancelled_at"
    t.integer "created_at", null: false
    t.integer "finished_at"
  end

  create_table "jobs", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "queue", null: false
    t.text "payload", size: :long, null: false
    t.integer "attempts", limit: 1, null: false, unsigned: true
    t.integer "reserved_at", unsigned: true
    t.integer "available_at", null: false, unsigned: true
    t.integer "created_at", null: false, unsigned: true
    t.index ["queue"], name: "jobs_queue_index"
  end

  create_table "migrations", id: { type: :integer, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "migration", null: false
    t.integer "batch", null: false
  end

  create_table "password_reset_tokens", primary_key: "email", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "token", null: false
    t.timestamp "created_at"
  end

  create_table "personal_access_tokens", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "tokenable_type", null: false
    t.bigint "tokenable_id", null: false, unsigned: true
    t.text "name", null: false
    t.string "token", limit: 64, null: false
    t.text "abilities"
    t.timestamp "last_used_at"
    t.timestamp "expires_at"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["expires_at"], name: "personal_access_tokens_expires_at_index"
    t.index ["token"], name: "personal_access_tokens_token_unique", unique: true
    t.index ["tokenable_type", "tokenable_id"], name: "personal_access_tokens_tokenable_type_tokenable_id_index"
  end

  create_table "playlist_songs", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "song_isrc", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.bigint "playlist_id", null: false, unsigned: true
    t.index ["playlist_id"], name: "playlist_songs_playlist_id_foreign"
    t.index ["song_isrc"], name: "playlist_songs_song_isrc_foreign"
  end

  create_table "playlists", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "name", null: false
    t.string "image_url"
  end

  create_table "plays", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "song_isrc", null: false
    t.integer "seconds_played", null: false
    t.string "station_id"
    t.index ["created_at"], name: "index_plays_on_created_at"
    t.index ["song_isrc"], name: "plays_song_isrc_foreign"
  end

  create_table "sessions", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "user_id", unsigned: true
    t.string "ip_address", limit: 45
    t.text "user_agent"
    t.text "payload", size: :long, null: false
    t.integer "last_activity", null: false
    t.index ["last_activity"], name: "sessions_last_activity_index"
    t.index ["user_id"], name: "sessions_user_id_index"
  end

  create_table "songs", primary_key: "isrc", id: :string, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "title", null: false
    t.string "artist", null: false
    t.string "album", null: false
    t.string "image_url", null: false
    t.integer "duration", null: false
    t.string "genre"
    t.integer "release_year"
    t.float "bpm"
    t.integer "deezer_rank"
    t.datetime "enriched_at"
    t.index ["genre"], name: "index_songs_on_genre"
    t.index ["release_year"], name: "index_songs_on_release_year"
  end

  create_table "talk_segments", id: { type: :string, limit: 64 }, charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "kind", null: false
    t.text "transcript"
    t.integer "duration"
    t.string "status", default: "pending", null: false
    t.text "meta", size: :long, collation: "utf8mb4_bin"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_talk_segments_on_expires_at"
    t.index ["kind", "status", "created_at"], name: "idx_on_kind_language_status_created_at_4f4243b56e"
    t.check_constraint "json_valid(`meta`)", name: "meta"
  end

  create_table "users", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.timestamp "email_verified_at"
    t.string "password", null: false
    t.string "remember_token", limit: 100
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["email"], name: "users_email_unique", unique: true
  end

  add_foreign_key "playlist_songs", "playlists", name: "playlist_songs_playlist_id_foreign", on_delete: :cascade
  add_foreign_key "playlist_songs", "songs", column: "song_isrc", primary_key: "isrc", name: "playlist_songs_song_isrc_foreign", on_delete: :cascade
  add_foreign_key "plays", "songs", column: "song_isrc", primary_key: "isrc", name: "plays_song_isrc_foreign", on_delete: :cascade
end
