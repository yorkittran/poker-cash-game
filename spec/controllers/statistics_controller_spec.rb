# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatisticsController, type: :controller do
  let(:user) { create(:user) }
  let(:game) { create(:game, created_by: user) }

  before { sign_in user }

  describe 'GET #index' do
    let!(:session1) { create(:cash_session, :profitable, user: user) }
    let!(:session2) { create(:cash_session, :losing, user: user) }

    it 'returns http success' do
      get :index
      expect(response).to have_http_status(:success)
    end

    it 'assigns user statistics' do
      get :index

      expect(assigns(:total_games)).to eq(user.games_played)
      expect(assigns(:total_hands_won)).to eq(user.hands_won)
      expect(assigns(:total_bankroll)).to eq(user.total_bankroll)
    end

    it 'assigns cash sessions' do
      get :index

      expect(assigns(:cash_sessions)).to include(session1, session2)
      expect(assigns(:total_profit)).to be_present
      expect(assigns(:win_rate)).to be_present
    end

    context 'with JSON format' do
      it 'returns statistics as JSON' do
        get :index, format: :json
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response['user']).to be_present
        expect(json_response['cash_sessions']).to be_an(Array)
        expect(json_response['total_profit']).to be_present
        expect(json_response['win_rate']).to be_present
      end

      it 'includes user information' do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response['user']['username']).to eq(user.username)
        expect(json_response['user']['total_bankroll']).to eq(user.total_bankroll)
      end

      it 'includes session details' do
        get :index, format: :json

        json_response = JSON.parse(response.body)
        session_data = json_response['cash_sessions'].first

        expect(session_data['game_id']).to be_present
        expect(session_data['buyin']).to be_present
        expect(session_data['cashout']).to be_present
        expect(session_data['profit_loss']).to be_present
      end
    end

    context 'with no sessions' do
      before do
        CashSession.destroy_all
        user.update!(games_played: 0)
      end

      it 'handles zero games gracefully' do
        get :index
        expect(assigns(:win_rate)).to eq(0)
      end
    end
  end

  describe 'GET #show' do
    let!(:hand1) { create(:hand, :completed, game: game, hand_number: 1) }
    let!(:hand2) { create(:hand, :completed, game: game, hand_number: 2) }
    let!(:my_session) { create(:cash_session, game: game, user: user) }

    it 'returns http success' do
      get :show, params: { id: game.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns game and hands' do
      get :show, params: { id: game.id }

      expect(assigns(:game)).to eq(game)
      expect(assigns(:hands)).to include(hand1, hand2)
    end

    it 'only shows completed hands' do
      incomplete_hand = create(:hand, game: game, hand_number: 3, completed_at: nil)

      get :show, params: { id: game.id }

      expect(assigns(:hands)).not_to include(incomplete_hand)
    end

    it 'orders hands by most recent first' do
      get :show, params: { id: game.id }

      expect(assigns(:hands).first).to eq(hand2)
    end

    context 'with JSON format' do
      it 'returns game statistics as JSON' do
        get :show, params: { id: game.id }, format: :json
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response['game']).to be_present
        expect(json_response['hands']).to be_an(Array)
        expect(json_response['my_sessions']).to be_an(Array)
      end

      it 'includes hand details' do
        get :show, params: { id: game.id }, format: :json

        json_response = JSON.parse(response.body)
        hand_data = json_response['hands'].first

        expect(hand_data['hand_number']).to be_present
        expect(hand_data['pot']).to be_present
        expect(hand_data['community_cards']).to be_an(Array)
        expect(hand_data['winners']).to be_an(Array)
      end

      it 'includes player actions for each hand' do
        user2 = create(:user)
        create(:player_action, hand: hand1, user: user, action_type: :fold, amount: 0, round: :preflop)
        create(:player_action, hand: hand1, user: user2, action_type: :call, amount: 20, round: :preflop)

        get :show, params: { id: game.id }, format: :json

        json_response = JSON.parse(response.body)
        hand_data = json_response['hands'].find { |h| h['hand_number'] == 1 }

        expect(hand_data['actions']).to be_an(Array)
        expect(hand_data['actions'].length).to eq(2)
      end
    end
  end

  describe 'authentication' do
    it 'requires login' do
      sign_out user

      get :index
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
