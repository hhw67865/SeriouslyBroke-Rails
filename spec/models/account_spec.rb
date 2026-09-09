# frozen_string_literal: true

require "rails_helper"

RSpec.describe Account do
  let(:user) { create(:user) }

  describe "validations", :aggregate_failures do
    it "needs a name, unique per user ignoring case" do
      create(:account, user: user, name: "Checking")

      expect(build(:account, user: user, name: "")).not_to be_valid
      expect(build(:account, user: user, name: "checking")).not_to be_valid
      expect(build(:account, user: create(:user), name: "checking")).to be_valid
    end

    it "opens at zero unless told otherwise" do
      expect(build(:account).opening_balance).to eq(0)
      expect(build(:account, opening_balance: "abc")).not_to be_valid
    end
  end

  describe ".open" do
    it "creates the account and makes it main when the user has none", :aggregate_failures do
      account = described_class.open(user, name: "Checking", balance: 120.5)

      expect(account).to be_persisted
      expect(account.opening_balance).to eq(120.5)
      expect(account.opened_on).to eq(user.today)
      expect(user.reload.main_account).to eq(account)
    end

    it "opens the day before the user's first entry" do
      create(:entry, :income, user: user, date: Date.new(2026, 3, 10)).item.category.update!(user: user)

      expect(described_class.open(user, name: "Checking", balance: 0).opened_on).to eq(Date.new(2026, 3, 9))
    end

    it "never steals main from an existing account" do
      first = described_class.open(user, name: "Checking", balance: 0)
      described_class.open(user, name: "Savings", balance: 0)

      expect(user.reload.main_account).to eq(first)
    end

    it "returns the invalid record with its errors", :aggregate_failures do
      account = described_class.open(user, name: "", balance: 0)

      expect(account).not_to be_persisted
      expect(account.errors[:name]).to include("can't be blank")
    end
  end

  describe "#destroy" do
    it "refuses to delete main", :aggregate_failures do
      main = create(:account, user: user)

      expect(main.destroy).to be(false)
      expect(main.errors[:base]).to include("This is your main account — everything flows through it")
    end

    it "deletes another account with its transfers and sends its income entries back to main", :aggregate_failures do
      main = create(:account, user: user)
      other = create(:account, user: user)
      create(:transfer, from_account: main, to_account: other)
      entry = create(:entry, :income, user: user, account: other)
      entry.item.category.update!(user: user)

      expect { other.destroy! }.to change(Transfer, :count).by(-1)
      expect(entry.reload.account).to be_nil
    end
  end
end
