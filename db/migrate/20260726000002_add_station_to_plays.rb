class AddStationToPlays < ActiveRecord::Migration[8.0]
  def change
    # Which station (if any) a play came from, e.g. "genre-rock"; nil for
    # manual playlist/search plays.
    add_column :plays, :station_id, :string
    # Repeat-avoidance and time-of-day profiles scan plays by time.
    add_index :plays, :created_at
  end
end
