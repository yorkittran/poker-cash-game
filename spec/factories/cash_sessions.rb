# frozen_string_literal: true

FactoryBot.define do
  factory :cash_session do
    association :game
    association :user
    buyin { 500 }
    cashout { 550 }
    profit_loss { 50 }
    hands_played { 10 }
    started_at { 1.hour.ago }
    ended_at { Time.current }

    trait :profitable do
      cashout { 750 }
      profit_loss { 250 }
    end

    trait :losing do
      cashout { 300 }
      profit_loss { -200 }
    end
  end
end
