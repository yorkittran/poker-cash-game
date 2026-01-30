class PlayerAction < ApplicationRecord
  belongs_to :hand
  belongs_to :user

  enum :action_type, { fold: "fold", check: "check", call: "call", bet: "bet", raise: "raise", all_in: "all_in" }
  enum :round, { preflop: "preflop", flop: "flop", turn: "turn", river: "river" }

  validates :action_type, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_round, ->(round) { where(round: round) }
  scope :chronological, -> { order(:created_at) }
end
