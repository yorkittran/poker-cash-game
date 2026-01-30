module Games
  class DeckService
    def initialize(game)
      @game = game
    end

    def deal_hole_cards
      deck = deserialize_deck(@game.deck_state)
      active_players = @game.game_players.where(status: :active).by_position

      active_players.each do |player|
        hole_cards = [ deck.deal, deck.deal ].map(&:to_s)
        player.update!(hole_cards: hole_cards)
      end

      @game.update!(deck_state: serialize_deck(deck))
    end

    def post_blinds
      active_players = @game.game_players.where(status: :active).by_position
      return if active_players.count < 2

      @game.game_players.update_all(current_bet: 0)

      post_small_blind(active_players)
      post_big_blind(active_players)
    end

    def deal_flop
      deck = deserialize_deck(@game.deck_state)
      deck.deal

      flop = [ deck.deal, deck.deal, deck.deal ].map(&:to_s)
      @game.update!(
        community_cards: flop,
        deck_state: serialize_deck(deck)
      )
    end

    def deal_turn
      deck = deserialize_deck(@game.deck_state)
      deck.deal

      turn = deck.deal.to_s
      @game.update!(
        community_cards: @game.community_cards + [ turn ],
        deck_state: serialize_deck(deck)
      )
    end

    def deal_river
      deck = deserialize_deck(@game.deck_state)
      deck.deal

      river = deck.deal.to_s
      @game.update!(
        community_cards: @game.community_cards + [ river ],
        deck_state: serialize_deck(deck)
      )
    end

    def create_shuffled_deck
      deck = Holdem::Deck.new
      deck.shuffle!
      @game.update!(deck_state: serialize_deck(deck))
    end

    private

    def post_small_blind(active_players)
      sb_position = (@game.dealer_position + 1) % active_player_count
      sb_player = active_players.find_by(position: sb_position)
      return unless sb_player

      blind_amount = [ @game.small_blind, sb_player.chips ].min
      sb_player.update!(
        chips: sb_player.chips - blind_amount,
        current_bet: blind_amount
      )
      @game.update!(pot: @game.pot + blind_amount)
      sb_player.update!(status: :all_in) if sb_player.chips == 0
    end

    def post_big_blind(active_players)
      bb_position = (@game.dealer_position + 2) % active_player_count
      bb_player = active_players.find_by(position: bb_position)
      return unless bb_player

      blind_amount = [ @game.big_blind, bb_player.chips ].min
      bb_player.update!(
        chips: bb_player.chips - blind_amount,
        current_bet: blind_amount
      )
      @game.update!(pot: @game.pot + blind_amount)
      bb_player.update!(status: :all_in) if bb_player.chips == 0
    end

    def active_player_count
      @game.game_players.where(status: [ :active, :all_in, :folded ]).count
    end

    def serialize_deck(deck)
      cards = deck.instance_variable_get(:@deck)
      cards.map(&:to_s).to_json
    end

    def deserialize_deck(deck_state)
      card_strings = JSON.parse(deck_state)
      all_cards_deck = Holdem::Deck.new
      all_cards = all_cards_deck.instance_variable_get(:@deck)

      deck = Holdem::Deck.new
      deck.instance_variable_get(:@deck).clear

      card_strings.each do |card_str|
        matching_card = all_cards.find { |c| c.to_s == card_str }
        deck.instance_variable_get(:@deck) << matching_card if matching_card
      end

      deck
    end
  end
end
