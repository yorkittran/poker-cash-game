# frozen_string_literal: true

class GamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game, only: [:show, :join, :leave, :action]

  def index
    @games = Game.where(state: [:waiting, :in_progress]).order(created_at: :desc)
    @my_games = current_user.games.where(state: [:waiting, :in_progress])

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
    service = GameService.create_game(current_user, game_params)

    if service
      service.join_game(current_user, params[:initial_buyin].to_i)
      game = service.instance_variable_get(:@game)

      LobbyChannel.broadcast_update

      respond_to do |format|
        format.html { redirect_to game_path(game), notice: "Game created successfully!" }
        format.json { render json: { id: game.id, name: game.name, message: "Game created successfully!" }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Failed to create game" }
        format.json { render json: { error: "Failed to create game" }, status: :unprocessable_entity }
      end
    end
  end

  def join
    service = GameService.new(@game)
    buyin_amount = params[:buyin_amount].to_i

    if service.join_game(current_user, buyin_amount)
      broadcast_game_update(@game)

      LobbyChannel.broadcast_update

      respond_to do |format|
        format.html { redirect_to game_path(@game), notice: "Joined game successfully!" }
        format.json { render json: { message: "Joined game successfully!", game_id: @game.id }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to games_path, alert: "Failed to join game" }
        format.json { render json: { error: "Failed to join game" }, status: :unprocessable_entity }
      end
    end
  end

  def leave
    service = GameService.new(@game)

    if service.leave_game(current_user)
      broadcast_game_update(@game)

      LobbyChannel.broadcast_update

      respond_to do |format|
        format.html { redirect_to games_path, notice: "Left game successfully!" }
        format.json { render json: { message: "Left game successfully!" }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to game_path(@game), alert: "Failed to leave game" }
        format.json { render json: { error: "Failed to leave game" }, status: :unprocessable_entity }
      end
    end
  end

  def action
    service = GameService.new(@game)

    begin
      service.process_action(
        current_user,
        params[:action_type],
        params[:amount]&.to_i
      )

      @game.reload
      broadcast_game_update(@game)

      respond_to do |format|
        format.html { redirect_to game_path(@game), notice: "Action processed" }
        format.json do
          render json: {
            message: "Action processed",
            game_state: {
              round: @game.round,
              pot: @game.pot,
              community_cards: @game.community_cards,
              current_player_position: @game.current_player_position
            }
          }, status: :ok
        end
      end
    rescue GameService::InvalidActionError, GameService::NotPlayersTurnError, GameService::InsufficientChipsError => e
      respond_to do |format|
        format.html { redirect_to game_path(@game), alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
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

  def broadcast_game_update(game)
    GameChannel.broadcast_to(game, {
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
      players: game.game_players.by_position.includes(:user).map do |player|
        {
          id: player.id,
          user_id: player.user_id,
          username: player.user.username,
          position: player.position,
          chips: player.chips,
          status: player.status,
          is_current_player: player.position == game.current_player_position
        }
      end
    })
  end
end
