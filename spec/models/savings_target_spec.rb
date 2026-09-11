# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsTarget do
  let(:user) { create(:user) }
  let!(:checking) { create(:account, user: user, name: "Checking") }
  let(:emergency) { create(:account, user: user, name: "Emergency") }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  it "is a fixed target when it names no item, and a share when it does", :aggregate_failures do
    fixed = create(:savings_target, account: emergency, amount: 200)
    share = create(:savings_target, :share, account: emergency, item: paycheck, percent: 10)

    expect(fixed).to be_target
    expect(fixed.words).to eq("$200.00 a period")
    expect(share).to be_share
    expect(share.words).to eq("10% of Paycheck")
  end

  it "keeps the one figure its item implies", :aggregate_failures do
    fixed = build(:savings_target, account: emergency, amount: 200, percent: 5)
    share = build(:savings_target, :share, account: emergency, item: paycheck, percent: 10, amount: 50)

    expect(fixed).to be_valid
    expect(fixed.percent).to be_nil
    expect(share).to be_valid
    expect(share.amount).to be_nil
    expect(build(:savings_target, account: emergency, amount: nil)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: paycheck, percent: nil)).not_to be_valid
  end

  it "refuses checking, another user's item, an expense item, and a percent past 100 across accounts", :aggregate_failures do
    expect(build(:savings_target, account: checking)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: create(:item, :income))).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: create(:item, :expense, user: user))).not_to be_valid

    create(:savings_target, :share, account: emergency, item: paycheck, percent: 60)
    other = create(:account, user: user, name: "Brokerage")
    expect(build(:savings_target, :share, account: other, item: paycheck, percent: 40)).to be_valid
    expect(build(:savings_target, :share, account: other, item: paycheck, percent: 41)).not_to be_valid
  end

  it "allows one fixed row per account and one share per item per account", :aggregate_failures do
    create(:savings_target, account: emergency)
    create(:savings_target, :share, account: emergency, item: paycheck)

    expect(build(:savings_target, account: emergency)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: paycheck)).not_to be_valid
  end

  it "does not mistake an unsaved item's share for a collision with the account's fixed row", :aggregate_failures do
    create(:savings_target, account: emergency)

    unsaved_item_share = build(:savings_target, :share, account: emergency, item: build(:item, :income, user: user))

    expect(unsaved_item_share).to be_valid
  end

  it "asks its amount, or its percent of the item's typical income", :aggregate_failures do
    expect(build(:savings_target, amount: 200).ask).to eq(200)
    expect(build(:savings_target, :share, percent: 10).ask(typical_income: 3_400)).to eq(340)
    expect(build(:savings_target, :share, percent: 10).ask(typical_income: nil)).to eq(0)
  end
end
