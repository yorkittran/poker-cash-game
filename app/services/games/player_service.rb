module Games
  class PlayerService
    def initialize(game)
      @game = game
    end

    def join(user, buyin_amount)
      return false if @game.game_players.exists?(user: user)
      return false unless valid_buyin?(buyin_amount)
      return false if @game.game_players.count >= @game.max_players

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
      CashSession.create(
        game: @game,
        user: game_player.user,
        buyin: game_player.buyin_amount,
        cashout: game_player.chips,
        hands_played: @game.current_hand_number,
        started_at: game_player.created_at,
        ended_at: Time.current
      )
    end

    def update_user_bankroll(user, game_player)
      profit_loss = game_player.chips - game_player.buyin_amount
      user.update(total_bankroll: user.total_bankroll + profit_loss)
    end

    def check_game_completion
      remaining_players = @game.game_players.reload.count
      if remaining_players == 0
        @game.update!(state: :completed)
      elsif @game.in_progress? && remaining_players < 2
        @game.update!(state: :completed)
      end
    end
  end
end
