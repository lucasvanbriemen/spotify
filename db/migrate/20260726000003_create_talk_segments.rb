class CreateTalkSegments < ActiveRecord::Migration[8.0]
  def change
    # Primary key is the talk id (e.g. "talk-news-nl-2026072608"), mirroring
    # songs.isrc: the id doubles as the audio filename in storage/audio.
    create_table :talk_segments, id: { type: :string, limit: 64 } do |t|
      t.string :kind, null: false                # news | intro | weather
      t.string :language, null: false, limit: 5  # nl | en
      t.text :transcript                         # served by the lyrics endpoint
      t.integer :duration                        # seconds, measured after render
      t.string :status, null: false, default: "pending" # pending | ready | failed
      t.json :meta                               # prev_isrc/next_isrc/airs_at/headlines
      t.datetime :expires_at, null: false
      t.timestamps
      t.index [ :kind, :language, :status, :created_at ]
      t.index :expires_at
    end
  end
end
