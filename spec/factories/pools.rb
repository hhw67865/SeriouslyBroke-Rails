# frozen_string_literal: true

FactoryBot.define do
  # A POOL IS AN ACCOUNT (two-ledger spec §5, Task 8). The `:budget_pool` and `:savings_pool` traits
  # are gone with the types they named, and so is the `account { association :pool, :account }`
  # default that housed them — an account sits inside nothing.
  #
  # `:account` SURVIVES rather than being deleted from 60-odd call sites — `create(:pool, :account)`
  # still reads as what the fixture means — and it restates the type it is named for so the trait
  # is not an empty block that a later reader has to check the factory to understand.
  factory :pool do
    sequence(:name) { |n| "#{Faker::Bank.name} #{n}" }
    pool_type { :account }
    association :user

    trait :account do
      pool_type { :account }
    end

    # ** AN ACCOUNT THAT HAS SAID WHAT IT HOLDS (account-openings spec §3). ** `pools.opened_on` is
    # the whole of `HomePresenter#awaiting_opening?`: NULL means the account still has a row in the
    # "Your accounts" card and is OUT of the money row's "Elsewhere" tile, the accounts line and
    # `#collapsed_accounts`. A fixture that wants a settled account — money parked elsewhere, a card
    # with Rename and Delete on it, an overdraft on a finished account — says so with this trait.
    #
    # NOT THE DEFAULT, DELIBERATELY: a freshly minted account has not answered anything, which is
    # what the onboarding examples are about and what `AccountOpening` computes its opening day for.
    # The date is a bare marker here — the real one comes from `AccountOpening`, which is the only
    # thing that writes an opening entry to go with it.
    trait :opened do
      opened_on { Date.current }
    end

    # THE FIRST ACCOUNT A USER GETS IS THEIR MAIN ONE, the same rule
    # `BankAccountsController#create` applies for real — later accounts for the same user are left
    # alone, exactly as a second bank account never steals the role.
    #
    # `update_columns`, NOT `update!` (fix round 2): a system spec's browser thread can be
    # mid-request against this SAME user at the exact instant this callback fires, and `update!`
    # runs `has_many :pools`' implicit autosave VALIDATION over the whole collection — racing the
    # other thread's in-flight, not-yet-persisted build and failing with "Pools is invalid" on a
    # user and pool that are each individually fine. This write only ever sets a column to the id of
    # the record whose own callback is setting it — legal by construction, nothing
    # `default_account_is_own_account` would refuse — so skipping validation skips nothing this
    # write needed, and skipping the has_many autosave path is the whole point.
    after(:create) do |pool|
      if pool.user.default_account.blank?
        # rubocop:disable Rails/SkipsModelValidations
        pool.user.update_columns(default_account_id: pool.id)
        # rubocop:enable Rails/SkipsModelValidations
      end
    end
  end
end
