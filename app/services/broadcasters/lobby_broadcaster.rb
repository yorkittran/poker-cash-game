module Broadcasters
  class LobbyBroadcaster
    def self.broadcast
      new.broadcast
    end

    def self.games_list
      new.games_list
    end

    def broadcast
      ActionCable.server.broadcast("lobby", games_list)
    end

    def games_list
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
            current_players: game.game_players.where.not(status: :left).count,
            created_by: game.created_by.username,
            created_at: game.created_at
          }
        end
      }
    end
  end
end
