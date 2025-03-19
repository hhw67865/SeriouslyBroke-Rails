FactoryBot.define do
  factory :paycheck do
    date { "2025-03-19" }
    amount { "9.99" }
    description { "MyString" }
    income_source { nil }
  end
end
