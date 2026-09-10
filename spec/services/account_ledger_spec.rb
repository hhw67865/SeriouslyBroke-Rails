# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountLedger do
  let(:user) { create(:user, :biweekly) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:food) { create(:category, user: user, name: "Food") }
  let(:main) { create(:account, user: user, opening_balance: 100) }
  let(:savings) { create(:account, user: user) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:ledger) { described_class.new(user, today: today) }

  def earn(amount, on:, account: nil, category: salary)
    create(:entry, item: create(:item, category: category), amount: amount, date: on, account: account)
  end

  def spend(amount, on:)
    create(:entry, item: create(:item, category: food), amount: amount, date: on)
  end

  describe "#balance_of", :aggregate_failures do
    it "is opening plus what landed, minus what left, plus transfers in, minus transfers out" do
      main
      earn(50, on: today)
      earn(20, on: today, account: savings)
      spend(30, on: today)
      create(:transfer, from_account: main, to_account: savings, amount: 40, date: today)

      expect(ledger.balance_of(main)).to eq(80)
      expect(ledger.balance_of(savings)).to eq(60)
      expect(ledger.pot).to eq(80)
      expect(ledger.total_money).to eq(140)
    end

    it "refuses another user's account" do
      expect { ledger.balance_of(create(:account)) }.to raise_error(AccountLedger::NotAnAccount)
    end

    it "is zero for a user with no main account" do
      expect(described_class.new(create(:user), today: today).pot).to eq(0)
    end
  end

  describe "#typical_income" do
    let(:gifts) { create(:category, :income, :irregular, user: user, name: "Gifts") }

    it "averages regular income over the last two complete periods", :aggregate_failures do
      # Grid: ... Aug 7-20, Aug 21-Sep 3, [Sep 4-17 is today's period]
      earn(2000, on: Date.new(2026, 8, 7))
      earn(2200, on: Date.new(2026, 8, 25))
      earn(500, on: Date.new(2026, 8, 26), category: gifts)
      earn(999, on: Date.new(2026, 9, 5))

      expect(ledger.complete_periods(2)).to eq([Date.new(2026, 8, 7)..Date.new(2026, 8, 20), Date.new(2026, 8, 21)..Date.new(2026, 9, 3)])
      expect(ledger.typical_income).to eq(2100)
    end

    it "uses one period when only one is complete since the first entry" do
      earn(2000, on: Date.new(2026, 8, 10))
      earn(2200, on: Date.new(2026, 8, 25))

      expect(ledger.typical_income).to eq(2200)
    end

    it "is nil with no complete period", :aggregate_failures do
      expect(ledger.typical_income).to be_nil
      earn(2000, on: Date.new(2026, 9, 5))
      expect(ledger.typical_income).to be_nil
    end
  end

  describe "Account#balance and #correct_balance", :aggregate_failures do
    it "reads through the ledger and corrects by moving the opening balance" do
      main
      spend(30, on: today)

      expect(main.balance).to eq(70)
      main.correct_balance(250)
      expect(main.reload.opening_balance).to eq(280)
      expect(main.balance).to eq(250)
    end

    it "refuses a figure that is not a number, and moves nothing" do
      main

      expect(main.correct_balance("abc")).to be(false)
      expect(main.correct_balance("")).to be(false)
      expect(main.errors[:opening_balance]).to include("is not a number")
      expect(main.reload.opening_balance).to eq(100)
    end
  end
end
