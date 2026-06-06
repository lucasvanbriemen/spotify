class CreateSongs < ActiveRecord::Migration[8.0]
  def change
    # Songs are identified by their ISRC (a 12-character industry code), not
    # an auto-increment id — mirrors the Laravel schema.
    create_table :songs, id: :string, primary_key: :isrc do |t|
      t.string :title
      t.string :artist
      t.string :album
      t.string :image_url
      t.integer :duration

      t.timestamps
    end
  end
end
