class StatisticsController < ApplicationController
  before_action :authenticate_user!

  def index
    @total_games = current_user.games_played
    @total_hands_won = current_user.hands_won
    @total_bankroll = current_user.total_bankroll

    @cash_sessions = current_user.cash_sessions
                                 .includes(:game)
                                 .order(ended_at: :desc)
                                 .limit(20)

    @profitable_sessions = @cash_sessions.where("profit_loss > 0")
    @total_profit = @cash_sessions.sum(:profit_loss)
    @win_rate = @total_games > 0 ? (@profitable_sessions.count.to_f / @total_games * 100).round(2) : 0

    respond_to do |format|
      format.html
      format.json do
        render json: {
          user: {
            username: current_user.username,
            total_bankroll: @total_bankroll,
            games_played: @total_games,
            hands_won: @total_hands_won
          },
          cash_sessions: @cash_sessions.map { |s|
            {
              game_id: s.game_id,
              game_name: s.game.name,
              buyin: s.buyin,
              cashout: s.cashout,
              profit_loss: s.profit_loss,
              hands_played: s.hands_played,
              started_at: s.started_at,
              ended_at: s.ended_at
            }
          },
          total_profit: @total_profit,
          win_rate: @win_rate
        }
      end
    end
  end

  def show
    @game = Game.find(params[:id])
    @hands = @game.hands.where.not(completed_at: nil).order(created_at: :desc).includes(:player_actions)
    @my_sessions = @game.cash_sessions.where(user: current_user)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          game: {
            id: @game.id,
            name: @game.name,
            state: @game.state
          },
          hands: @hands.map { |h|
            {
              hand_number: h.hand_number,
              dealer_position: h.dealer_position,
              pot: h.pot,
              community_cards: h.community_cards,
              winners: h.winners,
              actions: h.player_actions.order(:created_at).map { |a|
                {
                  username: a.user.username,
                  action_type: a.action_type,
                  amount: a.amount,
                  round: a.round
                }
              }
            }
          },
          my_sessions: @my_sessions.map { |s|
            {
              buyin: s.buyin,
              cashout: s.cashout,
              profit_loss: s.profit_loss,
              hands_played: s.hands_played
            }
          }
        }
      end
    end
  end
end
