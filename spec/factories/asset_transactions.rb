FactoryBot.define do
  factory :asset_transaction do
    date { "2025-03-19" }
    amount { "9.99" }
    description { "MyText" }
    asset { nil }
  end
end
