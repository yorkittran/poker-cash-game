# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Game, type: :model do
  describe 'validations' do
    let(:user) { create(:user) }
    subject { build(:game, created_by: user) }

    it 'validates presence of name' do
      game = build(:game, created_by: user, name: nil)
      expect(game).not_to be_valid
      expect(game.errors[:name]).to include("can't be blank")
    end

    it 'validates uniqueness of name' do
      create(:game, created_by: user, name: "Table 1")
      game = build(:game, created_by: user, name: "Table 1")
      expect(game).not_to be_valid
    end

    it 'validates numericality of small_blind' do
      game = build(:game, created_by: user, small_blind: 0)
      expect(game).not_to be_valid
    end

    it 'validates max_players is between 2 and 9' do
      game = build(:game, created_by: user, max_players: 1)
      expect(game).not_to be_valid

      game = build(:game, created_by: user, max_players: 10)
      expect(game).not_to be_valid

      game = build(:game, created_by: user, max_players: 6)
      expect(game).to be_valid
    end
  end

  describe 'associations' do
    it { should have_many(:game_players).dependent(:destroy) }
    it { should have_many(:users).through(:game_players) }
    it { should have_many(:hands).dependent(:destroy) }
    it { should have_many(:cash_sessions).dependent(:destroy) }
    it { should belong_to(:created_by).class_name('User') }
  end

  describe 'enums' do
    it 'defines state enum' do
      expect(Game.states).to eq('waiting' => 'waiting', 'in_progress' => 'in_progress', 'completed' => 'completed')
    end

    it 'defines round enum' do
      expect(Game.rounds).to eq('preflop' => 'preflop', 'flop' => 'flop', 'turn' => 'turn', 'river' => 'river', 'showdown' => 'showdown')
    end
  end

  describe 'scopes' do
    let!(:waiting_game) { create(:game, state: :waiting) }
    let!(:in_progress_game) { create(:game, :in_progress) }
    let!(:completed_game) { create(:game, :completed) }

    it 'filters by state' do
      expect(Game.waiting).to include(waiting_game)
      expect(Game.waiting).not_to include(in_progress_game)
    end
  end
end
