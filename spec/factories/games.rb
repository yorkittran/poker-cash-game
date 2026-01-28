# frozen_string_literal: true

FactoryBot.define do
  factory :game do
    sequence(:name) { |n| "Poker Table #{n}" }
    small_blind { 10 }
    big_blind { 20 }
    max_players { 6 }
    min_buyin { 100 }
    max_buyin { 1000 }
    state { :waiting }
    pot { 0 }
    current_hand_number { 0 }
    dealer_position { 0 }
    community_cards { [] }

    association :created_by, factory: :user

    trait :in_progress do
      state { :in_progress }
      round { :preflop }
    end

    trait :completed do
      state { :completed }
    end
  end
end
