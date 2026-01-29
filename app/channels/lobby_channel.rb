# frozen_string_literal: true

class LobbyChannel < ApplicationCable::Channel
  def subscribed
    stream_from "lobby"
  end

  def unsubscribed
    stop_all_streams
  end

  def request_games_list
    transmit(games_list_data)
  end

  private

  def games_list_data
    {
      type: "games_list",
      games: Game.active_games.includes(:game_players, :created_by).map do |game|
        {
          id: game.id,
          name: game.name,
          state: game.state,
          small_blind: game.small_blind,
          big_blind: game.big_blind,
          min_buyin: game.min_buyin,
          max_buyin: game.max_buyin,
          max_players: game.max_players,
          current_players: game.game_players.count,
          created_by: game.created_by.username,
          created_at: game.created_at
        }
      end
    }
  end

  def self.broadcast_update
    ActionCable.server.broadcast("lobby", games_list_data_static)
  end

  def self.games_list_data_static
    {
      type: "games_list",
      games: Game.active_games.includes(:game_players, :created_by).map do |game|
        {
          id: game.id,
          name: game.name,
          state: game.state,
          small_blind: game.small_blind,
          big_blind: game.big_blind,
          min_buyin: game.min_buyin,
          max_buyin: game.max_buyin,
          max_players: game.max_players,
          current_players: game.game_players.count,
          created_by: game.created_by.username,
          created_at: game.created_at
        }
      end
    }
  end
end
