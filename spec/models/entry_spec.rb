# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entry, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:item) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:date) }
  end

  describe "money handling" do
    it "stores decimal values correctly" do
      entry = create(:entry, amount: 15.99)
      expect(entry.amount).to eq(15.99)
    end
  end

  describe "delegations" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }
    let(:entry) { create(:entry, item: item) }

    it "delegates category to item" do
      expect(entry.category).to eq(category)
    end

    it "delegates user to item" do
      expect(entry.user).to eq(user)
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:expense_entry) { create(:entry, :expense, user: user) }
    let!(:income_entry) { create(:entry, :income, user: user) }

    describe ".expenses" do
      it "returns only expense entries", :aggregate_failures do
        expect(described_class.expenses).to include(expense_entry)
        expect(described_class.expenses).not_to include(income_entry)
      end
    end

    describe ".income" do
      it "returns only income entries", :aggregate_failures do
        expect(described_class.incomes).to include(income_entry)
        expect(described_class.incomes).not_to include(expense_entry)
      end
    end

    # `Entry.savings` IS GONE (plan 3, task 5) — it was the scope `PoolCalculator#savings_entries_total`
    # and `PoolBalanceLedger`'s `:savings` term both summed, and both died in the same commit.
    it "does not answer .savings at all" do
      expect(described_class).not_to respond_to(:savings)
    end
  end

  # THE PURPOSE LEDGER'S NARROWING, IN ONE SCOPE (two-ledger spec §4) — `CategoryLedger::
  # ENTRY_CATEGORY_ID` bounded to a single category, and the port of `.reaching_pool`, which is the
  # same sentence about a pool. `HoldingCalculator` asks it for the expense term of every balance,
  # so it is the one place "which entries drain THIS category" is spelled: a second spelling would
  # be free to disagree with the batched ledger that computes the same figure for a whole screen.
  #
  # BOTH DIRECTIONS, because the funded gate is the whole of what the scope adds over walking
  # `item → category`: an entry dated on or after `funded_since` drains the category, and one dated
  # before it drains AVAILABLE and must be absent here. The boundary day itself is included, which
  # is the arm `Category#counts_spending_on?` mirrors in Ruby.
  describe ".draining" do
    let(:user) { create(:user) }
    let(:food) { create(:category, :expense, user: user, name: "Food", funded_since: Date.new(2026, 8, 1)) }

    it "returns the entries dated from funded_since on, and no others", :aggregate_failures do
      item = create(:item, category: food)
      on_the_day = create(:entry, item: item, amount: 20, date: Date.new(2026, 8, 1))
      after_it = create(:entry, item: item, amount: 30, date: Date.new(2026, 8, 5))
      before_it = create(:entry, item: item, amount: 40, date: Date.new(2026, 7, 31))
      elsewhere = create(:entry, item: create(:item, category: create(:category, :expense, :funded, user: user)))

      expect(described_class.draining(food)).to contain_exactly(on_the_day, after_it)
      expect(described_class.draining(food)).not_to include(before_it, elsewhere)
    end

    # A category that was never funded holds nothing, so nothing drains it — its whole history is
    # available's. Without this, a scope that dropped the `funded_since IS NULL` arm would look
    # right on every funded fixture in the suite.
    it "returns nothing for a category that has never been funded" do
      unfunded = create(:category, :expense, user: user, name: "Unfunded")
      create(:entry, item: create(:item, category: unfunded), amount: 20)

      expect(described_class.draining(unfunded)).to be_empty
    end
  end

  # THREE BLOCKS ARE DELETED HERE, ALL ABOUT ONE COLUMN (two-ledger spec §2, Task 8).
  # `entries.pool_id` was a per-entry "paid from" override on the pool a category's spending
  # reached, and §2 rules the lane out of existence: the pot is where cash leaves, whatever the
  # entry names. With the column went `#effective_pool` and its lookup table of entry-pool /
  # category-pool / default-account cells, `#pool_must_belong_to_user`, and
  # `#income_must_land_in_an_account` — the "second channel" whose twin on `Category` is gone for
  # the same reason. What replaces all of it is `.draining` above: a category's own spending, gated
  # by `funded_since`.
end
