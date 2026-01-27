class CreatePlayerActions < ActiveRecord::Migration[7.2]
  def change
    create_table :player_actions do |t|
      t.references :hand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action_type
      t.integer :amount
      t.string :round

      t.timestamps
    end
  end
end
