FactoryBot.define do
  factory :expense do
    name { "MyString" }
    amount { "9.99" }
    date { "2025-03-19" }
    frequency { 1 }
    category { nil }
  end
end
