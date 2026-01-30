class Game < ApplicationRecord
  belongs_to :created_by, class_name: "User", foreign_key: "created_by_user_id"
  has_many :game_players, dependent: :destroy
  has_many :users, through: :game_players
  has_many :hands, dependent: :destroy
  has_many :cash_sessions, dependent: :destroy

  enum :state, { waiting: "waiting", in_progress: "in_progress", completed: "completed" }, default: :waiting
  enum :round, { preflop: "preflop", flop: "flop", turn: "turn", river: "river" }, default: :preflop

  scope :active_games, -> { where(state: [ :waiting, :in_progress ]) }

  validates :name, presence: true, uniqueness: true
  validates :small_blind, :big_blind, :max_players, :min_buyin, :max_buyin, presence: true, numericality: { greater_than: 0 }
  validates :max_players, inclusion: { in: 2..9 }
  validates :pot, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
