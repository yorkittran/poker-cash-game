# frozen_string_literal: true

FactoryBot.define do
  factory :game_player do
    association :game
    association :user
    position { 0 }
    chips { 500 }
    buyin_amount { 500 }
    status { :active }
    hole_cards { [] }

    trait :folded do
      status { :folded }
    end

    trait :all_in do
      status { :all_in }
      chips { 0 }
    end

    trait :left do
      status { :left }
      cashout_amount { 400 }
    end
  end
end
