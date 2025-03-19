FactoryBot.define do
  factory :category do
    name { "MyString" }
    minimum_amount { "9.99" }
    color { "MyString" }
    order { 1 }
    user { nil }
  end
end
