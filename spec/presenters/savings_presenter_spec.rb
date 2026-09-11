# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:ledger) { ClaimLedger.new(user, today: today) }

  it "reads checking's figures off the ledger", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: create(:category, user: user), starts_on: Date.new(2026, 1, 1))
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))

    expect(presenter.checking).to eq(checking)
    expect(presenter.checking_balance).to eq(4_000)
    expect(presenter.budget_claim).to eq(400)
    expect(presenter.savings_claim).to eq(200)
    expect(presenter.claimed).to eq(600)
    expect(presenter.free).to eq(3_400)
  end

  context "with a targeted account carrying a fixed target, a share, a transfer and an adjustment, and an untargeted one" do
    let!(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }
    let(:lines) { presenter.rows.index_by(&:name) }

    before do
      create(:account, user: user, name: "Joint", opening_balance: 2_000)
      paycheck = create(:item, :income, user: user, name: "Paycheck")
      create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
      create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
      create(:transfer, from_account: checking, to_account: emergency, amount: 150, date: Date.new(2026, 8, 28))
      create(:adjustment, source: emergency, amount: -20, date: Date.new(2026, 9, 6))
    end

    it "builds one line per savings account, targeted or not" do
      expect(lines.keys).to eq(["Emergency", "Joint"])
    end

    it "gives the targeted line its balance, claim, accrual and target words", :aggregate_failures do
      expect(lines["Emergency"]).to have_attributes(balance: 650, claim: 230, accrued: 180)
      expect(lines["Emergency"].target_words).to eq("$200.00 a period, plus 10% of Paycheck")
      expect(lines["Emergency"].mode_words).to eq("keeps extra")
      expect(lines["Emergency"].since).to eq(Date.new(2026, 8, 21))
    end

    it "carries the targeted line's transfer and adjustment, and marks it transferable", :aggregate_failures do
      expect(lines["Emergency"].moved_words).to eq("+$150.00 in on Aug 28")
      expect(lines["Emergency"].adjustments.map(&:amount)).to eq([-20])
      expect(lines["Emergency"]).to be_transferable
    end

    it "leaves the untargeted line with nothing claimed", :aggregate_failures do
      expect(lines["Joint"]).not_to be_targeted
      expect(lines["Joint"].claim).to eq(0)
    end

    it "totals the savings and what is owed", :aggregate_failures do
      expect(presenter.savings_total).to eq(2_650)
      expect(presenter.owed_total).to eq(230)
    end
  end
end
