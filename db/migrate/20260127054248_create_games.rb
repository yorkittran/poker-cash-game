class CreateGames < ActiveRecord::Migration[7.2]
  def change
    create_table :games do |t|
      t.string :name
      t.integer :small_blind
      t.integer :big_blind
      t.integer :max_players
      t.integer :min_buyin
      t.integer :max_buyin
      t.string :state
      t.integer :current_hand_number
      t.integer :dealer_position
      t.integer :current_player_position
      t.integer :pot
      t.string :round
      t.json :community_cards
      t.text :deck_state
      t.integer :created_by_user_id

      t.timestamps
    end
  end
end
