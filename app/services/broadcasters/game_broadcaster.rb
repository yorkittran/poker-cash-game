module Broadcasters
  class GameBroadcaster
    def self.broadcast(game, current_user: nil)
      new(game, current_user: current_user).broadcast
    end

    def self.game_state(game, current_user:)
      new(game, current_user: current_user).game_state
    end

    def initialize(game, current_user: nil)
      @game = game
      @current_user = current_user
    end

    def broadcast
      @game.reload
      GameChannel.broadcast_to(@game, broadcast_game_state)
    end

    def game_state
      current_hand = @game.hands.order(:created_at).last
      players_data = @game.game_players.reload.by_position.includes(:user)
      max_bet = players_data.maximum(:current_bet) || 0

      {
        type: "game_state",
        game: game_data(max_bet),
        players: players_data.map { |player| player_data(player, current_hand) },
        actions: actions_data(current_hand),
        winners: current_hand&.winners,
        your_player_id: current_player&.id,
        your_position: current_player&.position,
        your_hole_cards: current_player&.hole_cards,
        is_your_turn: current_player&.position == @game.current_player_position
      }
    end

    def broadcast_game_state
      current_hand = @game.hands.order(:created_at).last
      players_data = @game.game_players.reload.by_position.includes(:user)
      max_bet = players_data.maximum(:current_bet) || 0

      {
        type: "game_state",
        game: game_data(max_bet),
        players: players_data.map { |player| player_data(player, current_hand) },
        actions: actions_data(current_hand),
        winners: current_hand&.winners
      }
    end

    private

    def game_data(max_bet)
      {
        id: @game.id,
        name: @game.name,
        state: @game.state,
        pot: @game.pot,
        round: @game.round,
        community_cards: @game.community_cards,
        current_hand_number: @game.current_hand_number,
        current_player_position: @game.current_player_position,
        dealer_position: @game.dealer_position,
        small_blind: @game.small_blind,
        big_blind: @game.big_blind,
        current_bet: max_bet,
        showdown_mode: @game.showdown_mode
      }
    end

    def player_data(player, current_hand)
      ended_by_showdown = current_hand&.ended_by_showdown == true
      show_hole_cards = (@current_user && player.user_id == @current_user.id) ||
                        (ended_by_showdown && player.status.in?([ "active", "all_in" ]))

      {
        id: player.id,
        user_id: player.user_id,
        username: player.user.username,
        position: player.position,
        chips: player.chips,
        status: player.status,
        ready: player.ready,
        current_bet: player.current_bet,
        hole_cards: show_hole_cards ? player.hole_cards : nil,
        is_current_player: player.position == @game.current_player_position
      }
    end

    def actions_data(current_hand)
      return [] unless current_hand

      PlayerAction.where(hand_id: current_hand.id)
                  .order(:created_at)
                  .includes(:user)
                  .map do |action|
        {
          username: action.user.username,
          action_type: action.action_type,
          amount: action.amount,
          round: action.round
        }
      end
    end

    def current_player
      return nil unless @current_user
      @current_player ||= @game.game_players.find_by(user: @current_user)
    end
  end
end
