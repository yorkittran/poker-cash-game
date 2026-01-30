# frozen_string_literal: true

FactoryBot.define do
  factory :hand do
    association :game
    hand_number { 1 }
    dealer_position { 0 }
    small_blind { 10 }
    big_blind { 20 }
    pot { 0 }
    community_cards { [] }
    winners { [] }

    trait :completed do
      pot { 100 }
      community_cards { [ "Ah", "Kd", "Qc", "Js", "Td" ] }
      winners { [ { user_id: 1, username: "player1", amount: 100, hand_name: "Royal Flush" } ] }
      completed_at { Time.current }
    end
  end
end
