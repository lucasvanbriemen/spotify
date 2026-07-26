class AddEnrichmentToSongs < ActiveRecord::Migration[8.0]
  def change
    add_column :songs, :genre, :string
    add_column :songs, :release_year, :integer
    add_column :songs, :bpm, :float
    add_column :songs, :deezer_rank, :integer
    add_column :songs, :enriched_at, :datetime
    add_index :songs, :genre
    add_index :songs, :release_year
  end
end
