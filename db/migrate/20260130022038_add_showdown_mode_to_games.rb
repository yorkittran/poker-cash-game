class AddShowdownModeToGames < ActiveRecord::Migration[7.2]
  def change
    add_column :games, :showdown_mode, :boolean, default: false, null: false
  end
end
