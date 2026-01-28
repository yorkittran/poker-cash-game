# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "player#{n}" }
    password { "password123" }
    password_confirmation { "password123" }
    total_bankroll { 10000 }
    games_played { 0 }
    hands_won { 0 }
  end
end
