# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GamePlayer, type: :model do
  describe 'validations' do
    it 'validates position is between 0 and 8' do
      game_player = build(:game_player, position: -1)
      expect(game_player).not_to be_valid

      game_player = build(:game_player, position: 9)
      expect(game_player).not_to be_valid

      game_player = build(:game_player, position: 5)
      expect(game_player).to be_valid
    end

    it 'validates chips is greater than or equal to 0' do
      game_player = build(:game_player, chips: -1)
      expect(game_player).not_to be_valid

      game_player = build(:game_player, chips: 0)
      expect(game_player).to be_valid
    end

    it 'validates buyin_amount is greater than 0' do
      game_player = build(:game_player, buyin_amount: 0)
      expect(game_player).not_to be_valid

      game_player = build(:game_player, buyin_amount: 100)
      expect(game_player).to be_valid
    end
  end

  describe 'associations' do
    it { should belong_to(:game) }
    it { should belong_to(:user) }
  end

  describe 'enums' do
    it 'defines status enum' do
      expect(GamePlayer.statuses).to eq('active' => 'active', 'folded' => 'folded', 'all_in' => 'all_in', 'sitting_out' => 'sitting_out', 'left' => 'left')
    end
  end

  describe 'scopes' do
    let(:game) { create(:game) }
    let!(:active_player) { create(:game_player, game: game, status: :active, position: 0) }
    let!(:folded_player) { create(:game_player, game: game, status: :folded, position: 1) }
    let!(:left_player) { create(:game_player, :left, game: game, position: 2) }

    it 'returns active players' do
      expect(game.game_players.active_players).to include(active_player)
      expect(game.game_players.active_players).not_to include(folded_player)
    end

    it 'orders by position' do
      expect(game.game_players.by_position.first).to eq(active_player)
    end
  end
end
