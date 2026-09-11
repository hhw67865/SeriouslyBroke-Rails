# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds.rb", type: :task do
  it "plants a demo household the app can read", :aggregate_failures do
    expect { load Rails.root.join("db/seeds.rb") }.not_to change { Time.zone.name }

    user = User.find_by!(email: "demo@example.com")
    ledger = ClaimLedger.new(user)
    expect(user.accounts.count).to eq(4)
    expect(user.main_account.name).to eq("Checking")
    expect(user.rules.count).to eq(9)
    expect(ledger.claimed).to be > 0
    expect(ledger.account_ledger.typical_income).to be > 2_000
    expect(HomePresenter.new(user: user).troubles.map(&:kind)).not_to include(:structural)
  end
end
