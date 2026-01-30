class CashSession < ApplicationRecord
  belongs_to :game
  belongs_to :user

  validates :buyin, :cashout, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :hands_played, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  before_save :calculate_profit_loss

  scope :profitable, -> { where("profit_loss > 0") }
  scope :recent, -> { order(ended_at: :desc) }

  private

  def calculate_profit_loss
    self.profit_loss = (cashout || 0) - (buyin || 0)
  end
end
