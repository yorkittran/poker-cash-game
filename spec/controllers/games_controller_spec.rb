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
        gp.update!(hole_cards: [ "Ah", "Kd" ])

        get :show, params: { id: game.id }, format: :json
        json_response = JSON.parse(response.body)

        current_user_data = json_response['players'].find { |p| p['user_id'] == user.id }
        expect(current_user_data['hole_cards']).to eq([ "Ah", "Kd" ])
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

    it 'removes player from game' do
      post :leave, params: { id: game.id }

      game_player = game.game_players.find_by(user: user)
      expect(game_player).to be_nil
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

  # Note: Player actions are now handled via WebSocket (GameChannel)
  # See spec/channels/game_channel_spec.rb for action tests

  describe 'authentication' do
    it 'requires login for all actions' do
      sign_out user

      get :index
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
