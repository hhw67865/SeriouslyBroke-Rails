# frozen_string_literal: true

FactoryBot.define do
  factory :transfer do
    amount { 50 }
    date { Date.current }
    association :from_account, factory: :account
    to_account { association :account, user: from_account.user }
  end
end
