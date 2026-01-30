# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Games::PlayerService, type: :service do
  let(:user1) { create(:user, username: "alice", total_bankroll: 10000) }
  let(:user2) { create(:user, username: "bob", total_bankroll: 5000) }
  let(:user3) { create(:user, username: "charlie", total_bankroll: 200) }

  let(:game) do
    create(:game,
      name: "Test Table",
      small_blind: 10,
      big_blind: 20,
      max_players: 6,
      min_buyin: 100,
      max_buyin: 1000,
      created_by: user1
    )
  end

  let(:service) { described_class.new(game) }

  describe '#join' do
    context 'with sufficient bankroll' do
      it 'allows user to join the game' do
        expect(service.join(user1, 500)).to be_truthy
        expect(game.game_players.count).to eq(1)
      end

      it 'deducts buyin amount from user bankroll' do
        expect {
          service.join(user1, 500)
        }.to change { user1.reload.total_bankroll }.from(10000).to(9500)
      end

      it 'creates game_player with correct chips' do
        service.join(user1, 500)
        game_player = game.game_players.find_by(user: user1)

        expect(game_player.chips).to eq(500)
        expect(game_player.buyin_amount).to eq(500)
        expect(game_player.status).to eq('active')
      end
    end

    context 'with insufficient bankroll' do
      it 'prevents user from joining' do
        expect(service.join(user3, 500)).to be_falsey
        expect(game.game_players.count).to eq(0)
      end

      it 'does not deduct from bankroll' do
        expect {
          service.join(user3, 500)
        }.not_to change { user3.reload.total_bankroll }
      end
    end

    context 'when user is already in another active game' do
      let(:other_game) do
        create(:game,
          name: "Other Table",
          small_blind: 5,
          big_blind: 10,
          max_players: 6,
          min_buyin: 100,
          max_buyin: 1000,
          created_by: user2,
          state: :in_progress
        )
      end

      before do
        # User1 joins other_game
        other_service = described_class.new(other_game)
        other_service.join(user1, 500)
      end

      it 'prevents user from joining a second game' do
        expect(service.join(user1, 500)).to be_falsey
        expect(game.game_players.exists?(user: user1)).to be_falsey
      end

      it 'does not deduct additional funds' do
        initial_bankroll = user1.reload.total_bankroll
        service.join(user1, 500)
        expect(user1.reload.total_bankroll).to eq(initial_bankroll)
      end
    end

    context 'when user already in this game' do
      before do
        service.join(user1, 500)
      end

      it 'prevents duplicate join' do
        expect(service.join(user1, 500)).to be_falsey
        expect(game.game_players.where(user: user1).count).to eq(1)
      end
    end

    context 'with invalid buyin amount' do
      it 'rejects buyin below minimum' do
        expect(service.join(user1, 50)).to be_falsey
      end

      it 'rejects buyin above maximum' do
        expect(service.join(user1, 2000)).to be_falsey
      end
    end
  end

  describe '#leave' do
    before do
      service.join(user1, 500)
      @game_player = game.game_players.find_by(user: user1)
    end

    context 'when leaving with chips remaining' do
      it 'credits remaining chips to bankroll' do
        @game_player.update(chips: 700)  # Won $200

        expect {
          service.leave(user1)
        }.to change { user1.reload.total_bankroll }.from(9500).to(10200)
      end

      it 'creates cash session with correct profit' do
        @game_player.update(chips: 700)

        service.leave(user1)
        session = CashSession.last

        expect(session.user).to eq(user1)
        expect(session.game).to eq(game)
        expect(session.buyin).to eq(500)
        expect(session.cashout).to eq(700)
        expect(session.profit_loss).to eq(200)
      end

      it 'destroys game_player record' do
        service.leave(user1)
        expect(game.game_players.exists?(user: user1)).to be_falsey
      end
    end

    context 'when leaving with losses' do
      it 'credits remaining chips to bankroll' do
        @game_player.update(chips: 200)  # Lost $300

        expect {
          service.leave(user1)
        }.to change { user1.reload.total_bankroll }.from(9500).to(9700)
      end

      it 'creates cash session with negative profit' do
        @game_player.update(chips: 200)

        service.leave(user1)
        session = CashSession.last

        expect(session.profit_loss).to eq(-300)
      end
    end

    context 'when leaving with zero chips' do
      it 'does not change bankroll (already deducted on join)' do
        @game_player.update(chips: 0)  # Lost everything

        expect {
          service.leave(user1)
        }.not_to change { user1.reload.total_bankroll }
      end

      it 'creates cash session showing total loss' do
        @game_player.update(chips: 0)

        service.leave(user1)
        session = CashSession.last

        expect(session.buyin).to eq(500)
        expect(session.cashout).to eq(0)
        expect(session.profit_loss).to eq(-500)
      end
    end

    context 'when last player leaves' do
      it 'marks game as completed' do
        service.leave(user1)
        expect(game.reload.state).to eq('completed')
      end
    end

    context 'when multiple players and one leaves' do
      before do
        service.join(user2, 500)
        # Add a third player so we can test the >2 player scenario
        service.join(user3, 200)
        game.update(state: :in_progress)
      end

      it 'does not mark game as completed if 2+ players remain' do
        service.leave(user1)
        expect(game.reload.state).to eq('in_progress')
      end

      it 'marks game as completed if only 1 player remains' do
        service.leave(user1)
        service.leave(user2)
        # Only user3 remains, game should be completed
        expect(game.reload.state).to eq('completed')
      end
    end
  end

  describe '#rebuy' do
    before do
      service.join(user1, 500)
      @game_player = game.game_players.find_by(user: user1)
      @game_player.update(chips: 0, status: :sitting_out)
    end

    context 'with sufficient bankroll' do
      it 'allows rebuy' do
        expect(service.rebuy(user1, 500)).to be_truthy
      end

      it 'deducts rebuy amount from bankroll' do
        expect {
          service.rebuy(user1, 500)
        }.to change { user1.reload.total_bankroll }.from(9500).to(9000)
      end

      it 'adds chips to player' do
        service.rebuy(user1, 500)
        expect(@game_player.reload.chips).to eq(500)
        expect(@game_player.buyin_amount).to eq(1000)  # Original 500 + rebuy 500
      end
    end

    context 'with insufficient bankroll' do
      before do
        user1.update(total_bankroll: 100)
      end

      it 'prevents rebuy' do
        expect(service.rebuy(user1, 500)).to be_falsey
      end

      it 'does not modify chips or bankroll' do
        initial_bankroll = user1.reload.total_bankroll
        initial_chips = @game_player.reload.chips

        service.rebuy(user1, 500)

        expect(user1.reload.total_bankroll).to eq(initial_bankroll)
        expect(@game_player.reload.chips).to eq(initial_chips)
      end
    end
  end

  describe 'pot handling when players leave during game' do
    context 'when last player leaves during an in-progress game with pot' do
      before do
        # Setup: Two players join, game starts
        service.join(user1, 500)
        service.join(user2, 500)
        game.update!(
          state: :in_progress,
          pot: 150,  # There's money in the pot
          dealer_position: 0,
          current_player_position: 1
        )
        # Create a hand to track the pot
        game.hands.create!(
          hand_number: 1,
          dealer_position: 0,
          small_blind: game.small_blind,
          big_blind: game.big_blind,
          pot: 0  # Will be updated when pot is awarded
        )
      end

      it 'awards the pot to the last remaining player when opponent leaves' do
        player1 = game.game_players.find_by(user: user1)

        # Player 2 leaves, Player 1 should get the pot
        initial_chips = player1.chips
        service.leave(user2)

        expect(player1.reload.chips).to eq(initial_chips + 150)
        expect(game.reload.pot).to eq(0)
      end

      it 'includes pot in bankroll when last player cashes out' do
        player1 = game.game_players.find_by(user: user1)
        initial_bankroll = user1.reload.total_bankroll
        initial_chips = player1.chips

        # Player 2 leaves first (Player 1 gets the pot)
        service.leave(user2)

        # Player 1 leaves and cashes out (including the pot money)
        service.leave(user1)

        expected_bankroll = initial_bankroll + initial_chips + 150
        expect(user1.reload.total_bankroll).to eq(expected_bankroll)
      end

      it 'completes the current hand with winner information' do
        service.leave(user2)

        hand = game.hands.last
        expect(hand.winners).to be_present
        expect(hand.winners.first['user_id']).to eq(user1.id)
        expect(hand.winners.first['amount']).to eq(150)
        expect(hand.winners.first['hand_name']).to include('forfeit')
        expect(hand.completed_at).to be_present
      end

      it 'marks the game as completed' do
        service.leave(user2)
        expect(game.reload.state).to eq('completed')
      end
    end

    context 'when last player leaves without pot' do
      before do
        service.join(user1, 500)
        service.join(user2, 500)
        game.update!(
          state: :in_progress,
          pot: 0,  # No pot
          dealer_position: 0
        )
      end

      it 'does not award anything extra' do
        player1 = game.game_players.find_by(user: user1)
        initial_chips = player1.chips

        service.leave(user2)

        expect(player1.reload.chips).to eq(initial_chips)
      end
    end

    context 'when multiple players leave sequentially' do
      before do
        # Three players in game
        service.join(user1, 500)
        service.join(user2, 500)
        service.join(user3, 200)
        game.update!(
          state: :in_progress,
          pot: 300,
          dealer_position: 0
        )
        game.hands.create!(
          hand_number: 1,
          dealer_position: 0,
          small_blind: game.small_blind,
          big_blind: game.big_blind,
          pot: 0  # Will be updated when pot is awarded
        )
      end

      it 'awards pot only when down to last player' do
        player1 = game.game_players.find_by(user: user1)

        initial_chips_1 = player1.chips

        # First player leaves - game still has 2 players, no pot awarded
        service.leave(user3)
        expect(game.reload.pot).to eq(300)
        expect(player1.reload.chips).to eq(initial_chips_1)

        # Second player leaves - only 1 remains, pot awarded
        service.leave(user2)
        expect(game.reload.pot).to eq(0)
        expect(player1.reload.chips).to eq(initial_chips_1 + 300)
      end
    end
  end

  describe 'complete money flow scenario' do
    it 'tracks money correctly through multiple games' do
      # User starts with $10,000
      expect(user1.total_bankroll).to eq(10000)

      # Game 1: Buy in for $500
      service.join(user1, 500)
      expect(user1.reload.total_bankroll).to eq(9500)

      # Win $200, leave with $700
      game_player = game.game_players.find_by(user: user1)
      game_player.update(chips: 700)
      service.leave(user1)
      expect(user1.reload.total_bankroll).to eq(10200)

      # Game 2: Create new game and buy in for $1000
      game2 = create(:game,
        name: "Game 2",
        small_blind: 10,
        big_blind: 20,
        max_players: 6,
        min_buyin: 100,
        max_buyin: 1000,
        created_by: user2
      )
      service2 = described_class.new(game2)
      service2.join(user1, 1000)
      expect(user1.reload.total_bankroll).to eq(9200)

      # Lose $300, leave with $700
      game_player2 = game2.game_players.find_by(user: user1)
      game_player2.update(chips: 700)
      service2.leave(user1)
      expect(user1.reload.total_bankroll).to eq(9900)

      # Net result: Started with $10,000, ended with $9,900 (-$100 total)
      expect(user1.reload.total_bankroll).to eq(9900)
    end
  end
end
