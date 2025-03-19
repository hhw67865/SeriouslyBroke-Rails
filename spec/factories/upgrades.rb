FactoryBot.define do
  factory :upgrade do
    potential_income { "9.99" }
    minimum_downpayment { "9.99" }
    income_source { nil }
  end
end
