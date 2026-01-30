class AddCurrentBetToGamePlayers < ActiveRecord::Migration[7.2]
  def change
    add_column :game_players, :current_bet, :integer, default: 0, null: false
  end
end
