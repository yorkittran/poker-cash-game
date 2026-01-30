module Games
  class HandService
    def initialize(game)
      @game = game
      @deck_service = DeckService.new(game)
      @betting_service = BettingService.new(game)
      @winner_service = WinnerService.new(game)
    end

    def start_new_hand
      return false unless @game.in_progress?
      return false unless can_start_new_hand?

      @game.increment!(:current_hand_number)
      move_dealer_button

      hand = create_hand_record
      reset_game_state
      prepare_players
      setup_deck_and_deal
      @deck_service.post_blinds
      set_first_player

      hand
    end

    def start_new_hand_after_showdown
      players_with_chips = @game.game_players.where.not(status: :left).where("chips > 0")
      return false unless players_with_chips.count >= 2
      return false unless @game.in_progress?

      @game.game_players.where.not(status: :left).where(chips: 0).update_all(status: :sitting_out)

      start_new_hand
    end

    def should_enter_showdown_mode?
      active_players = @game.game_players.where(status: :active)
      all_in_players = @game.game_players.where(status: :all_in)

      return true if active_players.count == 0 && all_in_players.count >= 2
      return true if active_players.count == 1 && all_in_players.count >= 1

      false
    end

    def advance_to_next_round
      @game.game_players.update_all(current_bet: 0)

      case @game.round.to_sym
      when :preflop
        @deck_service.deal_flop
        @game.update!(round: :flop)
      when :flop
        @deck_service.deal_turn
        @game.update!(round: :turn)
      when :turn
        @deck_service.deal_river
        @game.update!(round: :river)
      when :river
        @winner_service.determine_winner
        return
      end

      set_first_player_for_round
    end

    def advance_showdown_round
      return false unless @game.showdown_mode?

      case @game.round.to_sym
      when :preflop
        @deck_service.deal_flop
        @game.update!(round: :flop)
      when :flop
        @deck_service.deal_turn
        @game.update!(round: :turn)
      when :turn
        @deck_service.deal_river
        @game.update!(round: :river)
      when :river
        @winner_service.determine_winner
        @game.update!(showdown_mode: false)
        return true
      end

      true
    end

    private

    def can_start_new_hand?
      return true if @game.current_hand_number == 0

      last_hand = @game.hands.order(:created_at).last
      last_hand&.winners&.present?
    end

    def create_hand_record
      @game.hands.create!(
        hand_number: @game.current_hand_number,
        dealer_position: @game.dealer_position,
        small_blind: @game.small_blind,
        big_blind: @game.big_blind,
        pot: 0
      )
    end

    def reset_game_state
      @game.update!(
        pot: 0,
        round: :preflop,
        community_cards: []
      )
    end

    def prepare_players
      @game.game_players.where.not(status: :left).where("chips > 0")
           .update_all(status: :active, hole_cards: nil)
      @game.game_players.where.not(status: :left).where(chips: 0)
           .update_all(status: :sitting_out, hole_cards: nil)
    end

    def setup_deck_and_deal
      @deck_service.create_shuffled_deck
      @deck_service.deal_hole_cards
    end

    def set_first_player
      @betting_service.set_next_player((@game.dealer_position + 3) % active_player_count)
    end

    def set_first_player_for_round
      players_who_can_act = @game.game_players.where(status: :active).by_position.to_a
      if players_who_can_act.any?
        dealer_pos = @game.dealer_position
        first_player = players_who_can_act.find { |p| p.position > dealer_pos } || players_who_can_act.first
        @betting_service.set_next_player(first_player.position)
      end
    end

    def move_dealer_button
      active_positions = @game.game_players.where.not(status: :left).pluck(:position).sort
      current_index = active_positions.index(@game.dealer_position) || 0
      next_dealer = active_positions[(current_index + 1) % active_positions.length]

      @game.update!(dealer_position: next_dealer)
    end

    def active_player_count
      @game.game_players.where(status: [ :active, :all_in, :folded ]).count
    end
  end
end
