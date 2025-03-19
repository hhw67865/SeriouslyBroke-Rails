FactoryBot.define do
  factory :task do
    description { "MyText" }
    completed { false }
    upgrade { nil }
  end
end
