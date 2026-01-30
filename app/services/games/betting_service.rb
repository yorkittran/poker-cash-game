module Games
  class BettingService
    class InvalidActionError < StandardError; end
    class InsufficientChipsError < StandardError; end
    class NotPlayersTurnError < StandardError; end

    def initialize(game)
      @game = game
    end

    def process_action(user, action_type, amount = nil)
      raise InvalidActionError, "Action type required" if action_type.nil?

      game_player = @game.game_players.find_by(user: user)
      raise InvalidActionError, "Player not in game" unless game_player
      raise NotPlayersTurnError, "Not your turn" unless current_player?(game_player)

      current_hand = @game.hands.order(:created_at).last
      raise InvalidActionError, "No active hand" unless current_hand

      execute_action(game_player, action_type, amount, current_hand)
    end

    def current_bet
      @game.game_players.maximum(:current_bet) || 0
    end

    def betting_round_complete?
      current_hand = @game.hands.order(:created_at).last
      return false unless current_hand

      active_players = @game.game_players.where(status: :active)
      all_in_players = @game.game_players.where(status: :all_in)
      players_in_hand = active_players.count + all_in_players.count

      return true if players_in_hand <= 1
      return true if active_players.count == 0

      actions_this_round = current_hand.player_actions.where(round: @game.round)
      players_acted = actions_this_round.pluck(:user_id).uniq

      max_bet = current_bet
      active_players.all? do |player|
        has_acted = players_acted.include?(player.user_id)
        has_matched_bet = player.current_bet >= max_bet
        has_acted && has_matched_bet
      end
    end

    def advance_to_next_player
      players_who_can_act = @game.game_players.where(status: :active).pluck(:position).sort
      return if players_who_can_act.empty?

      current_index = players_who_can_act.index(@game.current_player_position)

      next_position = if current_index.nil?
        players_who_can_act.find { |pos| pos > @game.current_player_position } ||
          players_who_can_act.first
      else
        players_who_can_act[(current_index + 1) % players_who_can_act.length]
      end

      @game.update!(current_player_position: next_position)
    end

    def set_next_player(position)
      @game.update!(current_player_position: position)
    end

    private

    def execute_action(game_player, action_type, amount, current_hand)
      hand_ended = case action_type.to_s.to_sym
      when :fold
        handle_fold(game_player, current_hand)
      when :check
        handle_check(game_player, current_hand)
        false
      when :call
        handle_call(game_player, current_hand)
        false
      when :bet, :raise
        handle_bet_or_raise(game_player, current_hand, amount)
        false
      when :all_in
        handle_all_in(game_player, current_hand)
        false
      else
        raise InvalidActionError, "Invalid action type"
      end

      hand_ended
    end

    def handle_fold(player, hand)
      player.update!(status: :folded)
      record_action(hand, player, :fold, 0)

      winner_service = WinnerService.new(@game)
      winner_service.check_for_winner_by_folds
    end

    def handle_check(player, hand)
      amount_to_call = current_bet - player.current_bet
      raise InvalidActionError, "Cannot check - must call #{amount_to_call} or raise" if amount_to_call > 0

      record_action(hand, player, :check, 0)
    end

    def handle_call(player, hand)
      amount_to_call = current_bet - player.current_bet
      raise InvalidActionError, "Nothing to call - use check instead" if amount_to_call <= 0

      call_amount = [ amount_to_call, player.chips ].min
      player.update!(
        chips: player.chips - call_amount,
        current_bet: player.current_bet + call_amount
      )
      @game.update!(pot: @game.pot + call_amount)

      player.update!(status: :all_in) if player.chips == 0

      record_action(hand, player, :call, call_amount)
    end

    def handle_bet_or_raise(player, hand, amount)
      raise InvalidActionError, "Amount must be specified" unless amount

      current_max_bet = current_bet
      amount_to_call = current_max_bet - player.current_bet
      min_raise = current_max_bet + @game.big_blind

      new_player_bet = amount.to_i
      raise InvalidActionError, "Raise must be at least #{min_raise}" if new_player_bet < min_raise

      chips_to_put_in = new_player_bet - player.current_bet
      raise InsufficientChipsError, "Not enough chips" if chips_to_put_in > player.chips
      raise InvalidActionError, "Must raise to at least #{player.current_bet}" if chips_to_put_in <= 0

      player.update!(
        chips: player.chips - chips_to_put_in,
        current_bet: new_player_bet
      )
      @game.update!(pot: @game.pot + chips_to_put_in)

      player.update!(status: :all_in) if player.chips == 0

      action_type = amount_to_call > 0 ? :raise : :bet
      record_action(hand, player, action_type, chips_to_put_in)
    end

    def handle_all_in(player, hand)
      amount = player.chips
      new_player_bet = player.current_bet + amount

      player.update!(
        chips: 0,
        status: :all_in,
        current_bet: new_player_bet
      )
      @game.update!(pot: @game.pot + amount)

      record_action(hand, player, :all_in, amount)
    end

    def record_action(hand, player, action_type, amount)
      PlayerAction.create!(
        hand: hand,
        user: player.user,
        action_type: action_type,
        amount: amount,
        round: @game.round
      )
    end

    def current_player?(game_player)
      game_player.position == @game.current_player_position
    end
  end
end
