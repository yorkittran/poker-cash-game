class GameChannel < ApplicationCable::Channel
  def subscribed
    game = Game.find(params[:game_id])
    stream_for game
  rescue StandardError => e
    Rails.logger.error "[GameChannel] Subscription error: #{e.class} - #{e.message}"
    reject
  end

  def unsubscribed
    stop_all_streams
  end

  def player_action(data)
    action_type = data["action_type"]

    unless action_type.present?
      transmit({ error: "Action type required" })
      return
    end

    game = Game.find(params[:game_id])
    amount = data["amount"]

    begin
      service = GameService.new(game)
      service.process_action(current_user, action_type, amount)

      Broadcasters::GameBroadcaster.broadcast(game)
    rescue GameService::InvalidActionError, GameService::NotPlayersTurnError, GameService::InsufficientChipsError => e
      transmit({ error: e.message })
    rescue StandardError => e
      Rails.logger.error "[GameChannel] Error: #{e.class} - #{e.message}"
      transmit({ error: "An error occurred processing your action" })
    end
  end

  def request_game_state(data = {})
    game = Game.find(params[:game_id])

    if game.in_progress?
      last_hand = game.hands.order(:created_at).last
      if last_hand&.completed_at && last_hand.winners.present? && Time.current - last_hand.completed_at >= 5.seconds
        game_service = GameService.new(game)
        if game_service.start_new_hand_after_showdown
          game.reload
          Broadcasters::GameBroadcaster.broadcast(game)
        end
      end
    end

    transmit(Broadcasters::GameBroadcaster.game_state(game, current_user: current_user))
  end

  def start_next_hand(data = {})
    game = Game.find(params[:game_id])

    last_hand = game.hands.order(:created_at).last
    unless last_hand&.winners&.present? && game.in_progress?
      transmit({ error: "Cannot start new hand at this time" })
      return
    end

    game_service = GameService.new(game)

    if game_service.start_new_hand_after_showdown
      game.reload
      Broadcasters::GameBroadcaster.broadcast(game)
    else
      transmit({ error: "Failed to start new hand" })
    end
  end

  def advance_showdown_round(data = {})
    game = Game.find(params[:game_id])

    unless game.showdown_mode?
      transmit({ error: "Game is not in showdown mode" })
      return
    end

    game_service = GameService.new(game)
    result = game_service.advance_showdown_round

    if result
      game.reload
      Broadcasters::GameBroadcaster.broadcast(game)
    else
      transmit({ error: "Failed to advance showdown round" })
    end
  end
end
