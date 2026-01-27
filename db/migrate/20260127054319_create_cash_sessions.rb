class CreateCashSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :cash_sessions do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :buyin
      t.integer :cashout
      t.integer :profit_loss
      t.integer :hands_played
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end
  end
end
