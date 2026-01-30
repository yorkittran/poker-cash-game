class GamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game, only: [ :show, :join ]

  def index
    @games = Game.where(state: [ :waiting, :in_progress ]).order(created_at: :desc)
    @my_games = current_user.games.where(state: [ :waiting, :in_progress ])

    respond_to do |format|
      format.html
      format.json do
        render json: @games.map { |g|
          {
            id: g.id,
            name: g.name,
            small_blind: g.small_blind,
            big_blind: g.big_blind,
            max_players: g.max_players,
            min_buyin: g.min_buyin,
            max_buyin: g.max_buyin,
            state: g.state,
            current_players: g.game_players.where.not(status: :left).count
          }
        }
      end
    end
  end

  def show
    @game_player = @game.game_players.find_by(user: current_user)
    @players = @game.game_players.by_position.includes(:user)
    @current_hand = @game.hands.order(:created_at).last

    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @game.id,
          name: @game.name,
          state: @game.state,
          round: @game.round,
          pot: @game.pot,
          community_cards: @game.community_cards,
          current_player_position: @game.current_player_position,
          players: @players.map { |p|
            player_data = {
              user_id: p.user_id,
              username: p.user.username,
              position: p.position,
              chips: p.chips,
              status: p.status
            }
            player_data[:hole_cards] = p.hole_cards if p.user_id == current_user.id
            player_data
          }
        }
      end
    end
  end

  def create
    buyin_amount = params[:initial_buyin].to_i

    if GamePlayer.joins(:game)
                  .where(user: current_user)
                  .where(games: { state: [:waiting, :in_progress] })
                  .exists?
      respond_to do |format|
        format.html { redirect_to games_path, alert: "You're already in an active game. Please leave it before creating a new one." }
        format.json { render json: { error: "Already in an active game" }, status: :unprocessable_entity }
      end
      return
    end

    if current_user.total_bankroll < buyin_amount
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Insufficient bankroll. You have $#{current_user.total_bankroll} but need $#{buyin_amount}." }
        format.json { render json: { error: "Insufficient bankroll" }, status: :unprocessable_entity }
      end
      return
    end

    service = GameService.create_game(current_user, game_params)

    if service && service.join_game(current_user, buyin_amount)
      game = service.instance_variable_get(:@game)

      Broadcasters::LobbyBroadcaster.broadcast

      respond_to do |format|
        format.html { redirect_to game_path(game), notice: "Game created successfully!" }
        format.json { render json: { id: game.id, name: game.name, message: "Game created successfully!" }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Failed to create game. Please check your inputs and try again." }
        format.json { render json: { error: "Failed to create game" }, status: :unprocessable_entity }
      end
    end
  end

  def join
    buyin_amount = params[:buyin_amount].to_i

    if GamePlayer.joins(:game)
                  .where(user: current_user)
                  .where(games: { state: [:waiting, :in_progress] })
                  .where.not(game_id: @game.id)
                  .exists?
      respond_to do |format|
        format.html { redirect_to games_path, alert: "You're already in another active game. Please leave it first." }
        format.json { render json: { error: "Already in another active game" }, status: :unprocessable_entity }
      end
      return
    end

    if current_user.total_bankroll < buyin_amount
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Insufficient bankroll. You have $#{current_user.total_bankroll} but need $#{buyin_amount}." }
        format.json { render json: { error: "Insufficient bankroll" }, status: :unprocessable_entity }
      end
      return
    end

    service = GameService.new(@game)

    if service.join_game(current_user, buyin_amount)
      Broadcasters::GameBroadcaster.broadcast(@game)
      Broadcasters::LobbyBroadcaster.broadcast

      respond_to do |format|
        format.html { redirect_to game_path(@game), notice: "Joined game successfully!" }
        format.json { render json: { message: "Joined game successfully!", game_id: @game.id }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Failed to join game. The table may be full or you may already be in this game." }
        format.json { render json: { error: "Failed to join game" }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def game_params
    params.require(:game).permit(
      :name,
      :small_blind,
      :big_blind,
      :max_players,
      :min_buyin,
      :max_buyin
    )
  end
end
