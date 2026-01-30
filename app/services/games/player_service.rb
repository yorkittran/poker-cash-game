module Games
  class PlayerService
    def initialize(game)
      @game = game
    end

    def join(user, buyin_amount)
      return false if @game.game_players.exists?(user: user)

      active_game_player = GamePlayer.joins(:game)
                                     .where(user: user)
                                     .where(games: { state: [:waiting, :in_progress] })
                                     .exists?
      return false if active_game_player

      return false unless valid_buyin?(buyin_amount)
      return false if user.total_bankroll < buyin_amount
      return false if @game.game_players.count >= @game.max_players

      user.update!(total_bankroll: user.total_bankroll - buyin_amount)

      position = find_available_position
      @game.game_players.create(
        user: user,
        position: position,
        chips: buyin_amount,
        buyin_amount: buyin_amount,
        status: :active,
        ready: false
      )
    end

    def leave(user)
      game_player = @game.game_players.find_by(user: user)
      return false unless game_player

      award_pot_to_last_player(game_player) if should_award_pot_to_last_player?

      create_cash_session(game_player)
      update_user_bankroll(user, game_player)
      game_player.destroy

      check_game_completion
      true
    end

    def toggle_ready(user)
      game_player = @game.game_players.find_by(user: user)
      return false unless game_player
      return false unless @game.waiting?

      game_player.update!(ready: !game_player.ready)
      game_player
    end

    def check_all_ready
      players = @game.game_players.where.not(status: :left)
      return false if players.count < 2

      players.all?(&:ready)
    end

    def rebuy(user, amount)
      game_player = @game.game_players.find_by(user: user)
      return false unless game_player
      return false unless valid_buyin?(amount)
      return false unless game_player.chips == 0
      return false unless game_player.status == "sitting_out"
      return false if user.total_bankroll < amount

      user.update!(total_bankroll: user.total_bankroll - amount)

      game_player.update!(
        chips: amount,
        buyin_amount: game_player.buyin_amount + amount,
        status: :sitting_out
      )

      true
    end

    private

    def valid_buyin?(amount)
      amount >= @game.min_buyin && amount <= @game.max_buyin
    end

    def find_available_position
      taken_positions = @game.game_players.pluck(:position)
      (0...@game.max_players).find { |p| !taken_positions.include?(p) }
    end

    def create_cash_session(game_player)
      profit_loss = game_player.chips - game_player.buyin_amount

      CashSession.create(
        game: @game,
        user: game_player.user,
        buyin: game_player.buyin_amount,
        cashout: game_player.chips,
        profit_loss: profit_loss,
        hands_played: @game.current_hand_number,
        started_at: game_player.created_at,
        ended_at: Time.current
      )
    end

    def update_user_bankroll(user, game_player)
      user.update(total_bankroll: user.total_bankroll + game_player.chips)
    end

    def should_award_pot_to_last_player?
      return false unless @game.in_progress?
      return false if @game.pot.nil? || @game.pot == 0

      active_players = @game.game_players.where.not(status: :left).count
      active_players <= 1
    end

    def award_pot_to_last_player(game_player)
      pot_amount = @game.pot
      game_player.update!(chips: game_player.chips + pot_amount)

      current_hand = @game.hands.order(:created_at).last
      if current_hand && current_hand.winners.blank?
        current_hand.update!(
          pot: pot_amount,
          winners: [{
            user_id: game_player.user_id,
            username: game_player.user.username,
            amount: pot_amount,
            hand_name: "Won by forfeit (all other players left)"
          }],
          completed_at: Time.current,
          ended_by_showdown: false
        )
      end

      @game.update!(pot: 0)

      Rails.logger.info "[PlayerService] Awarded pot of #{pot_amount} to #{game_player.user.username} (last player remaining)"
    end

    def check_game_completion
      remaining_players = @game.game_players.reload.count

      if remaining_players == 0
        @game.update!(state: :completed)
      elsif @game.in_progress? && remaining_players == 1
        last_player = @game.game_players.first
        if @game.pot.present? && @game.pot > 0
          award_pot_to_last_player(last_player)
        end

        @game.update!(state: :completed)
      elsif @game.in_progress? && remaining_players < 2
        @game.update!(state: :completed)
      end
    end
  end
end
