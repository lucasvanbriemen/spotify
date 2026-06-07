class CreatePlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists do |t|
      t.string :name, null: false
      t.string :image_url

      t.timestamps
    end
  end
end
