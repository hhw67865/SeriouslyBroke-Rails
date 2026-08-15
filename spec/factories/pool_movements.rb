# frozen_string_literal: true

FactoryBot.define do
  factory :pool_movement do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Time.zone.now }
    association :from_pool, factory: [:pool, :account]

    to_pool do
      association :pool, :budget_pool, user: from_pool.user, account: from_pool
    end
  end
end
