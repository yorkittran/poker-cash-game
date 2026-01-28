# frozen_string_literal: true

FactoryBot.define do
  factory :player_action do
    association :hand
    association :user
    action_type { :fold }
    amount { 0 }
    round { :preflop }
  end
end
