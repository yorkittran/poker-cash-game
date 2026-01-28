# frozen_string_literal: true

class GameService
  class InvalidActionError < StandardError; end
  class InsufficientChipsError < StandardError; end
  class NotPlayersTurnError < StandardError; end

  def initialize(game)
    @game = game
  end

  def self.create_game(user, params)
    game = Game.new(
      name: params[:name],
      small_blind: params[:small_blind],
      big_blind: params[:big_blind],
      max_players: params[:max_players] || 9,
      min_buyin: params[:min_buyin],
      max_buyin: params[:max_buyin],
      created_by: user,
      state: :waiting,
      pot: 0,
      current_hand_number: 0
    )

    if game.save
      new(game)
    else
      nil
    end
  end

  def join_game(user, buyin_amount)
    return false if @game.game_players.exists?(user: user)
    return false if buyin_amount < @game.min_buyin || buyin_amount > @game.max_buyin
    return false if @game.game_players.count >= @game.max_players

    taken_positions = @game.game_players.pluck(:position)
    position = (0...@game.max_players).find { |p| !taken_positions.include?(p) }

    game_player = @game.game_players.create(
      user: user,
      position: position,
      chips: buyin_amount,
      buyin_amount: buyin_amount,
      status: :active
    )

    start_game if @game.game_players.count >= 2 && @game.waiting?

    game_player
  end

  def leave_game(user)
    game_player = @game.game_players.find_by(user: user)
    return false unless game_player

    CashSession.create(
      game: @game,
      user: user,
      buyin: game_player.buyin_amount,
      cashout: game_player.chips,
      hands_played: @game.current_hand_number,
      started_at: game_player.created_at,
      ended_at: Time.current
    )

    profit_loss = game_player.chips - game_player.buyin_amount
    user.update(total_bankroll: user.total_bankroll + profit_loss)

    game_player.update(status: :left, cashout_amount: game_player.chips)
    true
  end

  def start_game
    return false unless @game.waiting?
    return false if @game.game_players.active_players.count < 2

    @game.update!(
      state: :in_progress,
      dealer_position: 0
    )

    start_new_hand
  end

  def start_new_hand
    return false unless @game.in_progress?

    @game.increment!(:current_hand_number)
    move_dealer_button

    hand = @game.hands.create!(
      hand_number: @game.current_hand_number,
      dealer_position: @game.dealer_position,
      small_blind: @game.small_blind,
      big_blind: @game.big_blind,
      pot: 0
    )

    @game.update!(
      pot: 0,
      round: :preflop,
      community_cards: []
    )

    @game.game_players.where.not(status: :left).update_all(status: :active, hole_cards: nil)

    deck = Holdem::Deck.new
    deck.shuffle!
    @game.update!(deck_state: serialize_deck(deck))

    deal_hole_cards(deck)
    post_blinds
    set_next_player((@game.dealer_position + 3) % active_player_count)

    hand
  end

  def deal_hole_cards(deck)
    active_players = @game.game_players.active_players.by_position

    active_players.each do |player|
      hole_cards = [deck.deal, deck.deal].map(&:to_s)
      player.update!(hole_cards: hole_cards)
    end

    @game.update!(deck_state: serialize_deck(deck))
  end

  def post_blinds
    active_players = @game.game_players.active_players.by_position
    return if active_players.count < 2

    sb_position = (@game.dealer_position + 1) % active_player_count
    sb_player = active_players.find_by(position: sb_position)

    if sb_player
      blind_amount = [@game.small_blind, sb_player.chips].min
      sb_player.update!(chips: sb_player.chips - blind_amount)
      @game.update!(pot: @game.pot + blind_amount)
    end

    bb_position = (@game.dealer_position + 2) % active_player_count
    bb_player = active_players.find_by(position: bb_position)

    if bb_player
      blind_amount = [@game.big_blind, bb_player.chips].min
      bb_player.update!(chips: bb_player.chips - blind_amount)
      @game.update!(pot: @game.pot + blind_amount)

      bb_player.update!(status: :all_in) if bb_player.chips == 0
    end
  end

  def process_action(user, action_type, amount = nil)
    game_player = @game.game_players.find_by(user: user)
    raise InvalidActionError, "Player not in game" unless game_player
    raise NotPlayersTurnError, "Not your turn" unless current_player?(game_player)

    current_hand = @game.hands.order(:created_at).last
    raise InvalidActionError, "No active hand" unless current_hand

    case action_type.to_sym
    when :fold
      handle_fold(game_player, current_hand)
    when :check
      handle_check(game_player, current_hand)
    when :call
      handle_call(game_player, current_hand)
    when :bet, :raise
      handle_bet_or_raise(game_player, current_hand, amount)
    when :all_in
      handle_all_in(game_player, current_hand)
    else
      raise InvalidActionError, "Invalid action type"
    end

    advance_to_next_round if betting_round_complete?

    true
  end

  private

  def handle_fold(player, hand)
    player.update!(status: :folded)
    record_action(hand, player, :fold, 0)

    check_for_winner_by_folds
  end

  def handle_check(player, hand)
    record_action(hand, player, :check, 0)
    advance_to_next_player
  end

  def handle_call(player, hand)
    call_amount = [@game.big_blind, player.chips].min
    player.update!(chips: player.chips - call_amount)
    @game.update!(pot: @game.pot + call_amount)

    player.update!(status: :all_in) if player.chips == 0

    record_action(hand, player, :call, call_amount)
    advance_to_next_player
  end

  def handle_bet_or_raise(player, hand, amount)
    raise InvalidActionError, "Amount must be specified" unless amount
    raise InsufficientChipsError, "Not enough chips" if amount > player.chips

    player.update!(chips: player.chips - amount)
    @game.update!(pot: @game.pot + amount)

    player.update!(status: :all_in) if player.chips == 0

    record_action(hand, player, :raise, amount)
    advance_to_next_player
  end

  def handle_all_in(player, hand)
    amount = player.chips
    player.update!(chips: 0, status: :all_in)
    @game.update!(pot: @game.pot + amount)

    record_action(hand, player, :all_in, amount)
    advance_to_next_player
  end

  def record_action(hand, player, action_type, amount)
    PlayerAction.create!(
      hand: hand,
      user: player.user,
      action_type: action_type,
      amount: amount,
      round: @game.round
    )
  end

  def current_player?(game_player)
    game_player.position == @game.current_player_position
  end

  def advance_to_next_player
    active_positions = @game.game_players.active_players.pluck(:position).sort
    current_index = active_positions.index(@game.current_player_position)

    if current_index
      next_position = active_positions[(current_index + 1) % active_positions.length]
      @game.update!(current_player_position: next_position)
    end
  end

  def set_next_player(position)
    @game.update!(current_player_position: position)
  end

  def betting_round_complete?
    active_count = @game.game_players.where(status: [:active, :all_in]).count
    folded_count = @game.game_players.where(status: :folded).count

    active_count <= 1 || (active_count + folded_count) == active_player_count
  end

  def advance_to_next_round
    case @game.round.to_sym
    when :preflop
      deal_flop
      @game.update!(round: :flop)
    when :flop
      deal_turn
      @game.update!(round: :turn)
    when :turn
      deal_river
      @game.update!(round: :river)
    when :river
      @game.update!(round: :showdown)
      determine_winner
    end

    first_active = @game.game_players.active_players.order(:position).first
    set_next_player(first_active.position) if first_active
  end

  def deal_flop
    deck = deserialize_deck(@game.deck_state)
    deck.deal

    flop = [deck.deal, deck.deal, deck.deal].map(&:to_s)
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
      community_cards: @game.community_cards + [turn],
      deck_state: serialize_deck(deck)
    )
  end

  def deal_river
    deck = deserialize_deck(@game.deck_state)
    deck.deal

    river = deck.deal.to_s
    @game.update!(
      community_cards: @game.community_cards + [river],
      deck_state: serialize_deck(deck)
    )
  end

  def determine_winner
    current_hand = @game.hands.order(:created_at).last
    active_players = @game.game_players.where(status: [:active, :all_in])

    return if active_players.empty?

    player_hands = active_players.map do |player|
      cards_string = (player.hole_cards + @game.community_cards).join(" ")
      {
        player: player,
        hand: Holdem::PokerHand.new(cards_string)
      }
    end

    best_hand = player_hands.max_by { |ph| ph[:hand] }
    winners = player_hands.select { |ph| ph[:hand] == best_hand[:hand] }

    pot_share = @game.pot / winners.length

    winners_data = winners.map do |winner|
      winner[:player].update!(chips: winner[:player].chips + pot_share)
      winner[:player].user.increment!(:hands_won)

      {
        user_id: winner[:player].user_id,
        username: winner[:player].user.username,
        amount: pot_share,
        hand_name: best_hand[:hand].to_s
      }
    end

    current_hand.update!(
      pot: @game.pot,
      winners: winners_data,
      completed_at: Time.current
    )

    @game.update!(pot: 0)
    start_new_hand
  end

  def check_for_winner_by_folds
    active_count = @game.game_players.where(status: [:active, :all_in]).count

    if active_count == 1
      winner = @game.game_players.find_by(status: [:active, :all_in])
      winner.update!(chips: winner.chips + @game.pot)

      current_hand = @game.hands.order(:created_at).last
      current_hand.update!(
        pot: @game.pot,
        winners: [{
          user_id: winner.user_id,
          username: winner.user.username,
          amount: @game.pot,
          hand_name: "Won by folds"
        }],
        completed_at: Time.current
      )

      @game.update!(pot: 0)
      start_new_hand
    end
  end

  def move_dealer_button
    active_positions = @game.game_players.where.not(status: :left).pluck(:position).sort
    current_index = active_positions.index(@game.dealer_position) || 0
    next_dealer = active_positions[(current_index + 1) % active_positions.length]

    @game.update!(dealer_position: next_dealer)
  end

  def active_player_count
    @game.game_players.where.not(status: :left).count
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
