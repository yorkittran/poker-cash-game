class Hand < ApplicationRecord
  belongs_to :game
  has_many :player_actions, dependent: :destroy

  validates :hand_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :small_blind, :big_blind, :pot, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where.not(completed_at: nil) }
  scope :recent, -> { order(completed_at: :desc) }
end
