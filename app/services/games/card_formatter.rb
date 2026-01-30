module Games
  class CardFormatter
    SYMBOL_TO_LETTER = { "♥" => "h", "♦" => "d", "♣" => "c", "♠" => "s" }.freeze

    def self.to_letter_format(card)
      rank = card[0]
      suit_char = card[1]
      suit_letter = SYMBOL_TO_LETTER[suit_char] || suit_char
      "#{rank}#{suit_letter}"
    end
  end
end
