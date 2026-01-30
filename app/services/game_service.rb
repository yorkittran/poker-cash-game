class GameService
  class InvalidActionError < StandardError; end
  class InsufficientChipsError < StandardError; end
  class NotPlayersTurnError < StandardError; end

  def initialize(game)
    @game = game
    @player_service = Games::PlayerService.new(game)
    @hand_service = Games::HandService.new(game)
    @betting_service = Games::BettingService.new(game)
  end

  def self.create_game(user, params)
    game = Game.new(
      name: params[:name],
      small_blind: params[:small_blind],
      big_blind: params[:big_blind],
      max_players: params[:max_players] || 9,
      min_buyin: params[:min_buyin],
      max_buyin: params[:max_buyin],
      created_by: user,
      state: :waiting,
      pot: 0,
      current_hand_number: 0
    )

    game.save ? new(game) : nil
  end

  def join_game(user, buyin_amount)
    @player_service.join(user, buyin_amount)
  end

  def leave_game(user)
    @player_service.leave(user)
  end

  def toggle_ready(user)
    game_player = @player_service.toggle_ready(user)
    return false unless game_player

    start_game if @player_service.check_all_ready
    game_player
  end

  def rebuy(user, amount)
    @player_service.rebuy(user, amount)
  end

  def start_game
    return false unless @game.waiting?
    return false if @game.game_players.active_players.count < 2

    @game.update!(
      state: :in_progress,
      dealer_position: 0
    )

    start_new_hand
  end

  def start_new_hand
    @hand_service.start_new_hand
  end

  def start_new_hand_after_showdown
    @hand_service.start_new_hand_after_showdown
  end

  def process_action(user, action_type, amount = nil)
    begin
      hand_ended = @betting_service.process_action(user, action_type, amount)
    rescue Games::BettingService::InvalidActionError => e
      raise InvalidActionError, e.message
    rescue Games::BettingService::InsufficientChipsError => e
      raise InsufficientChipsError, e.message
    rescue Games::BettingService::NotPlayersTurnError => e
      raise NotPlayersTurnError, e.message
    end

    return true if hand_ended

    if @betting_service.betting_round_complete?
      if @hand_service.should_enter_showdown_mode?
        @game.update!(showdown_mode: true)
      else
        @hand_service.advance_to_next_round
      end
    else
      @betting_service.advance_to_next_player
    end

    true
  end

  def should_enter_showdown_mode?
    @hand_service.should_enter_showdown_mode?
  end

  def advance_showdown_round
    @hand_service.advance_showdown_round
  end
end
