# frozen_string_literal: true

FactoryBot.define do
  factory :pool do
    sequence(:name) { |n| "#{Faker::Commerce.product_name} #{n}" }
    target_amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) } # e.g., 1000.00
    start_date { 1.year.ago.to_date }
    pool_type { :savings }
    association :user

    # EVERY POOL IS EITHER AN ACCOUNT OR LIVES IN ONE (plan 3, task 6). The default used to leave
    # `account` nil, which made the bare `create(:pool)` an account-less savings goal — the
    # ordinary shape before the cutover backfill and an impossible one after it:
    # `Pool#account_matches_pool_type` refuses it and the `pools_account_matches_pool_type` CHECK
    # constraint refuses it a second time, past the model.
    #
    # Housed HERE rather than by editing every call site, and the `:savings_pool` trait is now
    # what this line says (kept, because a spec that means "a goal inside an account" should be
    # able to say so). The `:account` trait overrides it back to nil, which is that type's own
    # rule.
    account { association :pool, :account, user: user }

    trait :account do
      pool_type { :account }
      sequence(:name) { |n| "#{Faker::Bank.name} #{n}" }
      target_amount { nil }
      account { nil }
    end

    trait :budget_pool do
      pool_type { :budget }
      target_amount { nil }
      account { association :pool, :account, user: user }
    end

    trait :savings_pool do
      pool_type { :savings }
      account { association :pool, :account, user: user }
    end
  end
end
