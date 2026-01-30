class LobbyChannel < ApplicationCable::Channel
  def subscribed
    stream_from "lobby"
  end

  def unsubscribed
    stop_all_streams
  end

  def request_games_list
    transmit(Broadcasters::LobbyBroadcaster.games_list)
  end
end
