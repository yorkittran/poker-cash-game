class GamePlayer < ApplicationRecord
  belongs_to :game
  belongs_to :user

  # Enums
  enum :status, { active: "active", folded: "folded", all_in: "all_in", sitting_out: "sitting_out", left: "left" }, default: :active

  # Validations
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 9 }
  validates :chips, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :buyin_amount, presence: true, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :game_id, message: "already in this game" }

  # Scopes
  scope :active_players, -> { where(status: [:active, :all_in]) }
  scope :by_position, -> { order(:position) }
end
