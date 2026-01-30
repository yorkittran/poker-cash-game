class AddEndedByShowdownToHands < ActiveRecord::Migration[7.2]
  def change
    add_column :hands, :ended_by_showdown, :boolean, default: false, null: false
  end
end
