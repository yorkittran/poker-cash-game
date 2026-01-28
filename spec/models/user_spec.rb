# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:username) }
    it { should validate_uniqueness_of(:username).case_insensitive }
    it { should validate_length_of(:username).is_at_least(3).is_at_most(20) }
  end

  describe 'associations' do
    it { should have_many(:game_players).dependent(:destroy) }
    it { should have_many(:games).through(:game_players) }
    it { should have_many(:player_actions).dependent(:destroy) }
    it { should have_many(:cash_sessions).dependent(:destroy) }
  end

  describe 'attributes' do
    let(:user) { create(:user) }

    it 'has default values for poker stats' do
      expect(user.total_bankroll).to eq(10000)
      expect(user.games_played).to eq(0)
      expect(user.hands_won).to eq(0)
    end
  end

  describe 'devise' do
    it 'does not require email' do
      user = build(:user)
      expect(user).to be_valid
    end
  end
end
