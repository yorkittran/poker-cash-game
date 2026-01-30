class ChangeDefaultBankrollForUsers < ActiveRecord::Migration[7.2]
  def up
    change_column_default :users, :total_bankroll, from: 0, to: 10000

    User.where(total_bankroll: 0).update_all(total_bankroll: 10000)
  end

  def down
    change_column_default :users, :total_bankroll, from: 10000, to: 0
  end
end
