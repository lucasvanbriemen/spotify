class CreateKaraokeQueueItems < ActiveRecord::Migration[8.0]
  def change
    create_table :karaoke_queue_items do |t|
      t.string :song_isrc, null: false
      # Copied rather than joined: a song only gets a songs row once it has
      # been cached, and the queue exists to line up songs nobody has played.
      t.string :title, null: false
      t.string :artist, null: false
      t.string :image_url
      t.string :added_by
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.datetime :played_at

      t.timestamps
    end

    add_index :karaoke_queue_items, [ :status, :position ]
  end
end
