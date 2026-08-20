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

      # MAIN-ACCOUNT SPEC §6, VIA `Category#pool_must_be_reachable`: a category may point only
      # at the user's default account or an envelope, so a bare `create(:pool, :account)` used
      # as a category's pool is refused the instant that user already has no default set. The
      # FIRST account any fixture mints for a user becomes that user's main account here, the
      # same rule `BankAccountsController#create` applies for real — later accounts for the same
      # user are left alone, exactly as a second bank account never steals the role.
      #
      # `update_columns`, NOT `update!` (fix round 2): a system spec's browser thread can be
      # mid-request against this SAME user (e.g. `PoolsController#new`'s `current_user.pools.new`,
      # unsaved in THAT thread's copy of the association) at the exact instant this callback
      # fires, and `update!` runs `has_many :pools`' implicit autosave VALIDATION over the whole
      # collection — racing the other thread's in-flight, not-yet-persisted build and failing
      # with "Pools is invalid" on a user and pool that are each individually fine (measured: the
      # pool reloads valid immediately after). This write only ever sets a column to the id of
      # the record whose own callback is setting it — legal by construction, nothing
      # `default_account_is_own_account` would refuse — so skipping validation skips nothing
      # this write needed, and skipping the has_many autosave path is the whole point.
      after(:create) do |p|
        if p.pool_type_account? && p.user.default_account.blank?
          # rubocop:disable Rails/SkipsModelValidations
          p.user.update_columns(default_account_id: p.id)
          # rubocop:enable Rails/SkipsModelValidations
        end
      end
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
