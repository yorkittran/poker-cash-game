class AddReadyToGamePlayers < ActiveRecord::Migration[7.2]
  def change
    add_column :game_players, :ready, :boolean, default: false, null: false
  end
end
