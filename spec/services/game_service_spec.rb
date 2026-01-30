# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameService, type: :service do
  let(:user1) { create(:user, username: "alice") }
  let(:user2) { create(:user, username: "bob") }
  let(:user3) { create(:user, username: "charlie") }

  def serialize_deck(deck)
    cards = deck.instance_variable_get(:@deck)
    cards.map(&:to_s).to_json
  end

  describe '.create_game' do
    let(:game_params) do
      {
        name: "High Stakes Table",
        small_blind: 10,
        big_blind: 20,
        max_players: 6,
        min_buyin: 100,
        max_buyin: 1000
      }
    end

    it 'creates a new game' do
      expect {
        GameService.create_game(user1, game_params)
      }.to change(Game, :count).by(1)
    end

    it 'sets the game creator' do
      service = GameService.create_game(user1, game_params)
      game = service.instance_variable_get(:@game)
      expect(game.created_by).to eq(user1)
    end

    it 'initializes game in waiting state' do
      service = GameService.create_game(user1, game_params)
      game = service.instance_variable_get(:@game)
      expect(game.state).to eq('waiting')
      expect(game.pot).to eq(0)
      expect(game.current_hand_number).to eq(0)
    end

    it 'returns nil if game creation fails' do
      invalid_params = game_params.merge(name: nil)
      service = GameService.create_game(user1, invalid_params)
      expect(service).to be_nil
    end
  end

  describe '#join_game' do
    let(:game) { create(:game, min_buyin: 100, max_buyin: 1000) }
    let(:service) { GameService.new(game) }

    context 'when joining is successful' do
      it 'adds a player to the game' do
        expect {
          service.join_game(user1, 500)
        }.to change(game.game_players, :count).by(1)
      end

      it 'assigns correct position and chips' do
        game_player = service.join_game(user1, 500)
        expect(game_player.chips).to eq(500)
        expect(game_player.buyin_amount).to eq(500)
        expect(game_player.status).to eq('active')
        expect(game_player.position).to be_between(0, 5)
      end

      it 'starts game when 2 players join and both are ready' do
        service.join_game(user1, 500)
        expect(game.reload.state).to eq('waiting')

        service.join_game(user2, 500)
        expect(game.reload.state).to eq('waiting')

        service.toggle_ready(user1)
        expect(game.reload.state).to eq('waiting')

        service.toggle_ready(user2)
        expect(game.reload.state).to eq('in_progress')
      end

      it 'assigns different positions to players' do
        gp1 = service.join_game(user1, 500)
        gp2 = service.join_game(user2, 600)
        expect(gp1.position).not_to eq(gp2.position)
      end
    end

    context 'when joining fails' do
      it 'rejects duplicate join' do
        service.join_game(user1, 500)
        result = service.join_game(user1, 500)
        expect(result).to be_falsey
      end

      it 'rejects buyin below minimum' do
        result = service.join_game(user1, 50)
        expect(result).to be_falsey
      end

      it 'rejects buyin above maximum' do
        result = service.join_game(user1, 2000)
        expect(result).to be_falsey
      end

      it 'rejects when game is full' do
        6.times { service.join_game(create(:user), 500) }
        result = service.join_game(create(:user), 500)
        expect(result).to be_falsey
      end
    end
  end

  describe '#leave_game' do
    let(:game) { create(:game) }
    let(:service) { GameService.new(game) }

    before do
      service.join_game(user1, 500)
      service.join_game(user2, 500)
    end

    it 'removes player from game' do
      service.leave_game(user1)
      game_player = game.game_players.find_by(user: user1)
      expect(game_player).to be_nil
    end

    it 'creates a cash session' do
      expect {
        service.leave_game(user1)
      }.to change(CashSession, :count).by(1)
    end

    it 'updates user bankroll' do
      game_player = game.game_players.find_by(user: user1)
      game_player.update!(chips: 600)

      expect {
        service.leave_game(user1)
      }.to change { user1.reload.total_bankroll }.by(100)
    end

    it 'records profit/loss correctly' do
      game_player = game.game_players.find_by(user: user1)
      game_player.update!(chips: 400)

      service.leave_game(user1)

      session = CashSession.last
      expect(session.profit_loss).to eq(-100)
      expect(session.buyin).to eq(500)
      expect(session.cashout).to eq(400)
    end

    it 'returns false for non-existent player' do
      result = service.leave_game(user3)
      expect(result).to be_falsey
    end
  end

  describe '#start_game' do
    let(:game) { create(:game) }
    let(:service) { GameService.new(game) }

    before do
      service.join_game(user1, 500)
      service.join_game(user2, 500)
    end

    it 'changes game state to in_progress' do
      game.update!(state: :waiting)
      service.start_game
      expect(game.reload.state).to eq('in_progress')
    end

    it 'starts the first hand' do
      game.update!(state: :waiting)
      expect {
        service.start_game
      }.to change(game.hands, :count).by(1)
    end

    it 'returns false if less than 2 players' do
      game.game_players.last.destroy
      result = service.start_game
      expect(result).to be_falsey
    end
  end

  describe '#start_new_hand' do
    let(:game) { create(:game, :in_progress) }
    let(:service) { GameService.new(game) }

    before do
      service.join_game(user1, 500)
      service.join_game(user2, 500)
      game.update!(state: :in_progress)
    end

    it 'increments hand number' do
      expect {
        service.start_new_hand
      }.to change { game.reload.current_hand_number }.by(1)
    end

    it 'creates a new hand record' do
      expect {
        service.start_new_hand
      }.to change(game.hands, :count).by(1)
    end

    it 'resets game state' do
      game.update!(pot: 100, community_cards: [ "Ah", "Kd" ])
      service.start_new_hand

      game.reload
      expect(game.pot).to eq(30)
      expect(game.round).to eq('preflop')
      expect(game.community_cards).to eq([])
    end

    it 'deals hole cards to all players' do
      service.start_new_hand

      game.game_players.each do |gp|
        expect(gp.reload.hole_cards).to be_present
        expect(gp.hole_cards.length).to eq(2)
      end
    end

    it 'posts blinds correctly' do
      initial_pot = game.pot
      service.start_new_hand

      expect(game.reload.pot).to eq(30)
    end

    it 'sets the dealer button' do
      service.start_new_hand
      expect(game.reload.dealer_position).to be >= 0
    end
  end

  describe '#process_action' do
    let(:game) { create(:game, :in_progress) }
    let(:service) { GameService.new(game) }
    let!(:game_player1) { create(:game_player, game: game, user: user1, chips: 500, position: 0, status: :active) }
    let!(:game_player2) { create(:game_player, game: game, user: user2, chips: 500, position: 1, status: :active) }
    let!(:game_player3) { create(:game_player, game: game, user: user3, chips: 500, position: 2, status: :active) }

    before do
      deck = Holdem::Deck.new
      deck.shuffle!

      game.update!(
        state: :in_progress,
        current_player_position: game_player1.position,
        deck_state: serialize_deck(deck)
      )
      create(:hand, game: game, hand_number: 1)
    end

    context 'fold action' do
      it 'marks player as folded' do
        service.process_action(user1, :fold)
        expect(game_player1.reload.status).to eq('folded')
      end

      it 'records the action' do
        expect {
          service.process_action(user1, :fold)
        }.to change(PlayerAction, :count).by(1)

        action = PlayerAction.last
        expect(action.action_type).to eq('fold')
        expect(action.user).to eq(user1)
      end

      it 'determines winner if only one player remains' do
        service.process_action(user1, :fold)
        game.update!(current_player_position: game_player2.position)
        service.process_action(user2, :fold)
        hand = game.hands.last
        expect(hand.winners).not_to be_empty
        expect(hand.completed_at).to be_present
      end
    end

    context 'check action' do
      it 'records check action' do
        expect {
          service.process_action(user1, :check)
        }.to change(PlayerAction, :count).by(1)

        action = PlayerAction.last
        expect(action.action_type).to eq('check')
      end

      it 'processes the action successfully' do
        expect {
          service.process_action(user1, :check)
        }.not_to raise_error

        expect(PlayerAction.last.action_type).to eq('check')
      end
    end

    context 'call action' do
      before do
        # Player 2 raises to create a bet that player 1 can call
        game.update!(current_player_position: game_player2.position)
        service.process_action(user2, :bet, 50)
        game.update!(current_player_position: game_player1.position)
      end

      it 'deducts chips from player' do
        service.process_action(user1, :call)

        expect(game_player1.reload.chips).to be < 500
      end

      it 'adds to pot' do
        service.process_action(user1, :call)

        expect(game.reload.pot).to be > 50
      end

      it 'marks player as all-in if no chips left' do
        game_player1.update!(chips: 10)
        service.process_action(user1, :call)

        expect(game_player1.reload.status).to eq('all_in')
      end
    end

    context 'raise action' do
      it 'requires amount parameter' do
        expect {
          service.process_action(user1, :raise, nil)
        }.to raise_error(GameService::InvalidActionError, "Amount must be specified")
      end

      it 'raises error if insufficient chips' do
        expect {
          service.process_action(user1, :raise, 1000)
        }.to raise_error(GameService::InsufficientChipsError)
      end

      it 'deducts chips and adds to pot' do
        initial_chips = game_player1.chips
        initial_pot = game.pot

        service.process_action(user1, :raise, 50)

        expect(game_player1.reload.chips).to eq(initial_chips - 50)
        expect(game.reload.pot).to eq(initial_pot + 50)
      end
    end

    context 'all_in action' do
      it 'moves all chips to pot' do
        service.process_action(user1, :all_in)

        expect(game_player1.reload.chips).to eq(0)
        expect(game_player1.status).to eq('all_in')
      end
    end

    context 'invalid actions' do
      it 'raises error if not player turn' do
        game.update!(current_player_position: game_player2.position)

        expect {
          service.process_action(user1, :call)
        }.to raise_error(GameService::NotPlayersTurnError)
      end

      it 'raises error if player not in game' do
        non_player = create(:user)
        expect {
          service.process_action(non_player, :call)
        }.to raise_error(GameService::InvalidActionError, "Player not in game")
      end

      it 'raises error for invalid action type' do
        expect {
          service.process_action(user1, :invalid_action)
        }.to raise_error(GameService::InvalidActionError, "Invalid action type")
      end
    end
  end
end
