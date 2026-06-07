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

ActiveRecord::Schema[8.0].define(version: 2026_06_06_000004) do
  create_table "playlist_songs", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "playlist_id", null: false
    t.string "song_isrc", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id", "song_isrc"], name: "index_playlist_songs_on_playlist_id_and_song_isrc", unique: true
    t.index ["playlist_id"], name: "index_playlist_songs_on_playlist_id"
    t.index ["song_isrc"], name: "fk_rails_974866b31a"
  end

  create_table "playlists", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plays", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "song_isrc", null: false
    t.integer "seconds_played", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["song_isrc"], name: "index_plays_on_song_isrc"
  end

  create_table "songs", primary_key: "isrc", id: :string, charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "title"
    t.string "artist"
    t.string "album"
    t.string "image_url"
    t.integer "duration"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "playlist_songs", "playlists", on_delete: :cascade
  add_foreign_key "playlist_songs", "songs", column: "song_isrc", primary_key: "isrc", on_delete: :cascade
  add_foreign_key "plays", "songs", column: "song_isrc", primary_key: "isrc", on_delete: :cascade
end
