class CreatePlays < ActiveRecord::Migration[8.0]
  def change
    # Raw per-listen data, aggregated by the stats endpoint.
    create_table :plays do |t|
      t.string :song_isrc, null: false
      t.integer :seconds_played, null: false

      t.timestamps
    end

    add_foreign_key :plays, :songs, column: :song_isrc, primary_key: :isrc, on_delete: :cascade
    add_index :plays, :song_isrc
  end
end
