class CreateHands < ActiveRecord::Migration[7.2]
  def change
    create_table :hands do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :hand_number
      t.integer :dealer_position
      t.integer :small_blind
      t.integer :big_blind
      t.json :community_cards
      t.integer :pot
      t.json :winners
      t.datetime :completed_at

      t.timestamps
    end
  end
end
