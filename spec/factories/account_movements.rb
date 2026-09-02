# frozen_string_literal: true

FactoryBot.define do
  # BOTH ENDS ARE ACCOUNTS OF ONE USER, which is the whole shape the table holds after the drop
  # (two-ledger spec §5). `to_pool` is minted for `from_pool`'s user rather than for a fresh one, so
  # the bare `create(:account_movement)` satisfies `#accounts_must_share_a_user` without a call site
  # having to say so.
  factory :account_movement do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Time.zone.now }
    association :from_pool, factory: [:pool, :account]

    to_pool { association :pool, :account, user: from_pool.user }
  end
end
