# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountsPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:main) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:home) { HomePresenter.new(user: user, today: today) }

  def rule_on(name, amount:)
    category = create(:category, user: user, name: name)
    create(:rule, category: category, amount: amount, starts_on: Date.new(2026, 1, 1))
  end

  it "reads the spending figures Home reads, never recomputed", :aggregate_failures do
    rule_on("Groceries", amount: 400)

    expect(presenter.spending).to eq(main)
    expect(presenter.spending_balance).to eq(home.in_checking)
    expect(presenter.claimed).to eq(home.total_claims)
    expect(presenter.free).to eq(home.free_to_spend)
  end

  it "builds a set-aside row with its balance, opened and moved words", :aggregate_failures do
    ally = create(:account, user: user, name: "Ally", opening_balance: 500, opened_on: Date.new(2026, 3, 1))
    create(:transfer, from_account: main, to_account: ally, amount: 2_000, date: Date.new(2026, 9, 1))

    row = presenter.set_aside.find { |r| r.account == ally }

    expect(row.balance).to eq(home.balance_of(ally))
    expect(row.opened_words).to eq("opened Mar 2026")
    expect(row.moved_words).to eq("+$2,000.00 in on Sep 1")
  end

  it "prints an outgoing transfer, and a dash where an account has none", :aggregate_failures do
    vanguard = create(:account, user: user, name: "Vanguard", opening_balance: 200)
    create(:transfer, from_account: vanguard, to_account: main, amount: 95, date: Date.new(2026, 6, 18))
    create(:account, user: user, name: "Untouched", opening_balance: 10)

    vanguard_row = presenter.set_aside.find { |r| r.account == vanguard }
    untouched_row = presenter.set_aside.find { |r| r.account.name == "Untouched" }

    expect(vanguard_row.opened_words).to be_nil
    expect(vanguard_row.moved_words).to eq("−$95.00 out on Jun 18")
    expect(untouched_row.moved_words).to eq("—")
  end

  it "totals the set-aside accounts, and reports nothing set aside for a one-account user", :aggregate_failures do
    expect(presenter.set_aside).to eq([])
    expect(presenter.set_aside_total).to eq(0)

    create(:account, user: user, name: "Ally", opening_balance: 500)
    create(:account, user: user, name: "Vanguard", opening_balance: 250)

    expect(described_class.new(user: user, today: today).set_aside_total).to eq(750)
  end
end
