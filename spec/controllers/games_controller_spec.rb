# frozen_string_literal: true

require 'rails_helper'
require 'holdem'

RSpec.describe GamesController, type: :controller do
  let(:user) { create(:user) }
  let(:game) { create(:game, created_by: user) }

  before { sign_in user }

  describe 'GET #index' do
    let!(:waiting_game) { create(:game, state: :waiting, created_by: user) }
    let!(:in_progress_game) { create(:game, :in_progress, created_by: user) }
    let!(:completed_game) { create(:game, :completed, created_by: user) }

    it 'returns http success' do
      get :index
      expect(response).to have_http_status(:success)
    end

    it 'assigns only active games' do
      get :index
      expect(assigns(:games)).to include(waiting_game, in_progress_game)
      expect(assigns(:games)).not_to include(completed_game)
    end

    context 'with JSON format' do
      it 'returns games as JSON' do
        get :index, format: :json
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response).to be_an(Array)
        expect(json_response.length).to eq(2)
      end
    end
  end

  describe 'GET #show' do
    before do
      create(:game_player, game: game, user: user, position: 0)
    end

    it 'returns http success' do
      get :show, params: { id: game.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns game, game_player, and players' do
      get :show, params: { id: game.id }
      expect(assigns(:game)).to eq(game)
      expect(assigns(:game_player)).to be_present
      expect(assigns(:players)).to be_present
    end

    context 'with JSON format' do
      it 'returns game details as JSON' do
        get :show, params: { id: game.id }, format: :json
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq(game.id)
        expect(json_response['players']).to be_an(Array)
      end

      it 'includes hole cards for current user only' do
        gp = game.game_players.find_by(user: user)
        gp.update!(hole_cards: ["Ah", "Kd"])

        get :show, params: { id: game.id }, format: :json
        json_response = JSON.parse(response.body)

        current_user_data = json_response['players'].find { |p| p['user_id'] == user.id }
        expect(current_user_data['hole_cards']).to eq(["Ah", "Kd"])
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        game: {
          name: "Test Table",
          small_blind: 10,
          big_blind: 20,
          max_players: 6,
          min_buyin: 100,
          max_buyin: 1000
        },
        initial_buyin: 500
      }
    end

    context 'with valid params' do
      it 'creates a new game' do
        expect {
          post :create, params: valid_params
        }.to change(Game, :count).by(1)
      end

      it 'auto-joins the creator' do
        post :create, params: valid_params
        game = Game.last
        expect(game.game_players.where(user: user)).to exist
      end

      it 'redirects to game page' do
        post :create, params: valid_params
        expect(response).to redirect_to(game_path(Game.last))
      end
    end

    context 'with JSON format' do
      it 'returns created game as JSON' do
        post :create, params: valid_params.merge(format: :json)
        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response['id']).to be_present
        expect(json_response['message']).to eq("Game created successfully!")
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          game: {
            name: nil,
            small_blind: 10,
            big_blind: 20,
            max_players: 6,
            min_buyin: 100,
            max_buyin: 1000
          },
          initial_buyin: 500
        }
      end

      it 'does not create a game' do
        expect {
          post :create, params: invalid_params
        }.not_to change(Game, :count)
      end

      it 'redirects to games page' do
        post :create, params: invalid_params
        expect(response).to redirect_to(games_path)
      end
    end
  end

  describe 'POST #join' do
    let(:valid_params) { { id: game.id, buyin_amount: 500 } }

    context 'with valid buyin' do
      it 'adds player to game' do
        expect {
          post :join, params: valid_params
        }.to change(game.game_players, :count).by(1)
      end

      it 'redirects to game page' do
        post :join, params: valid_params
        expect(response).to redirect_to(game_path(game))
      end
    end

    context 'with JSON format' do
      it 'returns success message as JSON' do
        post :join, params: valid_params.merge(format: :json)
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq("Joined game successfully!")
      end
    end

    context 'with invalid buyin' do
      let(:invalid_params) { { id: game.id, buyin_amount: 50 } }

      it 'does not add player' do
        expect {
          post :join, params: invalid_params
        }.not_to change(game.game_players, :count)
      end

      it 'redirects to games page' do
        post :join, params: invalid_params
        expect(response).to redirect_to(games_path)
      end
    end
  end

  describe 'POST #leave' do
    before do
      create(:game_player, game: game, user: user, position: 0, chips: 500, buyin_amount: 500)
    end

    it 'marks player as left' do
      post :leave, params: { id: game.id }

      game_player = game.game_players.find_by(user: user)
      expect(game_player.reload.status).to eq('left')
    end

    it 'creates cash session' do
      expect {
        post :leave, params: { id: game.id }
      }.to change(CashSession, :count).by(1)
    end

    it 'redirects to games page' do
      post :leave, params: { id: game.id }
      expect(response).to redirect_to(games_path)
    end

    context 'with JSON format' do
      it 'returns success message as JSON' do
        post :leave, params: { id: game.id, format: :json }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq("Left game successfully!")
      end
    end
  end

  describe 'POST #action' do
    let!(:game_player) { create(:game_player, game: game, user: user, position: 0, chips: 500) }
    let!(:other_player1) { create(:game_player, game: game, user: create(:user), position: 1, chips: 500) }
    let!(:other_player2) { create(:game_player, game: game, user: create(:user), position: 2, chips: 500) }
    let!(:hand) { create(:hand, game: game, hand_number: 1) }

    before do
      deck = Holdem::Deck.new
      deck.shuffle!
      game.update!(
        state: :in_progress,
        current_player_position: game_player.position,
        round: :preflop,
        deck_state: deck.deck.map(&:to_s).to_json
      )
    end

    context 'with valid action' do
      it 'processes fold action' do
        expect {
          post :action, params: { id: game.id, action_type: 'fold' }
        }.to change(PlayerAction, :count).by(1)

        expect(game_player.reload.status).to eq('folded')
      end

      it 'processes call action' do
        initial_chips = game_player.chips
        post :action, params: { id: game.id, action_type: 'call' }

        expect(game_player.reload.chips).to be < initial_chips
      end

      it 'processes raise action with amount' do
        post :action, params: { id: game.id, action_type: 'raise', amount: 50 }

        expect(game_player.reload.chips).to eq(450)
      end

      it 'redirects to game page' do
        post :action, params: { id: game.id, action_type: 'check' }
        expect(response).to redirect_to(game_path(game))
      end
    end

    context 'with JSON format' do
      it 'returns game state as JSON' do
        post :action, params: { id: game.id, action_type: 'check', format: :json }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq("Action processed")
        expect(json_response['game_state']).to be_present
        expect(json_response['game_state']['round']).to be_present
      end
    end

    context 'with invalid action' do
      it 'handles not player turn error' do
        game.update!(current_player_position: 999)

        post :action, params: { id: game.id, action_type: 'call' }
        expect(response).to redirect_to(game_path(game))
        expect(flash[:alert]).to be_present
      end

      it 'handles invalid action type' do
        post :action, params: { id: game.id, action_type: 'invalid' }
        expect(response).to redirect_to(game_path(game))
        expect(flash[:alert]).to be_present
      end

      context 'with JSON format' do
        it 'returns error as JSON' do
          game.update!(current_player_position: 999)

          post :action, params: { id: game.id, action_type: 'call', format: :json }
          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to be_present
        end
      end
    end
  end

  describe 'authentication' do
    it 'requires login for all actions' do
      sign_out user

      get :index
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
