# frozen_string_literal: true

FactoryBot.define do
  # A DATED, SIGNED DELTA ON A RULE'S ACCRUAL (computed-claims spec §3.3). The default is a positive
  # top-up dated now, because that is the shape with no second question to answer; every example that
  # cares about the sign or the date says so outright, since both are the whole subject of §3.3.
  factory :adjustment do
    rule { association :budget }
    amount { 100 }
    date { Time.current }

    # −$158 from the car fund: a release, a raid, or the negative half of a skip.
    trait :release do
      amount { -100 }
    end
  end
end
