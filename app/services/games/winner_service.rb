module Games
  class WinnerService
    def initialize(game)
      @game = game
    end

    def determine_winner
      current_hand = @game.hands.order(:created_at).last
      active_players = @game.game_players.where(status: [ :active, :all_in ])

      return if active_players.empty?

      player_hands = build_player_hands(active_players)
      winners = find_winners(player_hands)
      pot_share = @game.pot / winners.length

      winners_data = distribute_pot(winners, pot_share)

      current_hand.update!(
        pot: @game.pot,
        winners: winners_data,
        completed_at: Time.current,
        ended_by_showdown: true
      )
    end

    def check_for_winner_by_folds
      active_count = @game.game_players.where(status: [ :active, :all_in ]).count

      return false unless active_count == 1

      winner = @game.game_players.find_by(status: [ :active, :all_in ])
      winner.update!(chips: winner.chips + @game.pot)

      current_hand = @game.hands.order(:created_at).last
      current_hand.update!(
        pot: @game.pot,
        winners: [ {
          user_id: winner.user_id,
          username: winner.user.username,
          amount: @game.pot,
          hand_name: "Won by folds"
        } ],
        completed_at: Time.current,
        ended_by_showdown: false
      )

      true
    end

    private

    def build_player_hands(active_players)
      active_players.map do |player|
        all_cards = player.hole_cards + @game.community_cards
        cards_string = all_cards.map { |card| CardFormatter.to_letter_format(card) }.join(" ")
        {
          player: player,
          hand: Holdem::PokerHand.new(cards_string)
        }
      end
    end

    def find_winners(player_hands)
      best_hand = player_hands.max_by { |ph| ph[:hand] }
      player_hands.select { |ph| ph[:hand] == best_hand[:hand] }
    end

    def distribute_pot(winners, pot_share)
      winners.map do |winner|
        winner[:player].update!(chips: winner[:player].chips + pot_share)
        winner[:player].user.increment!(:hands_won)

        {
          user_id: winner[:player].user_id,
          username: winner[:player].user.username,
          amount: pot_share,
          hand_name: winner[:hand].to_s
        }
      end
    end
  end
end
