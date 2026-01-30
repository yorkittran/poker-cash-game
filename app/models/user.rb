class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  has_many :game_players, dependent: :destroy
  has_many :games, through: :game_players
  has_many :cash_sessions, dependent: :destroy
  has_many :player_actions, dependent: :destroy

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                      length: { minimum: 3, maximum: 20 },
                      format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only allows letters, numbers, and underscores" }

  def email_required?
    false
  end

  def email_changed?
    false
  end

  def will_save_change_to_email?
    false
  end
end
