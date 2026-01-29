# frozen_string_literal: true

class GameChannel < ApplicationCable::Channel
  def subscribed
    game = Game.find(params[:game_id])
    stream_for game
  end

  def unsubscribed
    stop_all_streams
  end

  def perform_action(data)
    game = Game.find(params[:game_id])
    action_type = data["action_type"]
    amount = data["amount"]

    begin
      service = GameService.new(game)
      service.process_action(current_user, action_type, amount)

      broadcast_game_state(game)
    rescue GameService::InvalidActionError, GameService::NotPlayersTurnError, GameService::InsufficientChipsError => e
      transmit({ error: e.message })
    end
  end

  def request_game_state
    game = Game.find(params[:game_id])
    transmit(game_state_data(game))
  end

  private

  def broadcast_game_state(game)
    game_state = game_state_data(game)
    GameChannel.broadcast_to(game, game_state)
  end

  def game_state_data(game)
    game_player = game.game_players.find_by(user: current_user)

    {
      type: "game_state",
      game: {
        id: game.id,
        name: game.name,
        state: game.state,
        pot: game.pot,
        round: game.round,
        community_cards: game.community_cards,
        current_hand_number: game.current_hand_number,
        current_player_position: game.current_player_position,
        small_blind: game.small_blind,
        big_blind: game.big_blind
      },
      players: game.game_players.by_position.map do |player|
        {
          id: player.id,
          user_id: player.user_id,
          username: player.user.username,
          position: player.position,
          chips: player.chips,
          status: player.status,
          hole_cards: player.user_id == current_user.id ? player.hole_cards : nil,
          is_current_player: player.position == game.current_player_position
        }
      end,
      your_player_id: game_player&.id,
      your_position: game_player&.position,
      your_hole_cards: game_player&.hole_cards,
      is_your_turn: game_player&.position == game.current_player_position
    }
  end
end
