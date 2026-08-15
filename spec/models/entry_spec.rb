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
    let!(:savings_entry) { create(:entry, :savings, user: user) }

    describe ".expenses" do
      it "returns only expense entries", :aggregate_failures do
        expect(described_class.expenses).to include(expense_entry)
        expect(described_class.expenses).not_to include(income_entry)
        expect(described_class.expenses).not_to include(savings_entry)
      end
    end

    describe ".income" do
      it "returns only income entries", :aggregate_failures do
        expect(described_class.incomes).to include(income_entry)
        expect(described_class.incomes).not_to include(expense_entry)
        expect(described_class.incomes).not_to include(savings_entry)
      end
    end

    describe ".savings" do
      it "returns only savings entries", :aggregate_failures do
        expect(described_class.savings).to include(savings_entry)
        expect(described_class.savings).not_to include(expense_entry)
        expect(described_class.savings).not_to include(income_entry)
      end
    end
  end

  describe "#effective_pool" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    it "uses the entry's own pool when set" do
      savings_account = create(:pool, :account, user: user, name: "Savings Account")
      category = create(:category, :income, user: user, pool: checking)
      entry = create(:entry, item: create(:item, category: category), pool: savings_account)

      expect(entry.effective_pool).to eq(savings_account)
    end

    it "falls back to the category's pool" do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = create(:entry, item: create(:item, category: category))

      expect(entry.effective_pool).to eq(groceries)
    end

    it "falls back to the user's default account when the category has no pool" do
      user.update!(default_account: checking)
      category = create(:category, :expense, user: user, pool: nil)
      entry = create(:entry, item: create(:item, category: category))

      expect(entry.effective_pool).to eq(checking)
    end

    it "is nil when nothing resolves" do
      category = create(:category, :expense, user: user, pool: nil)
      entry = create(:entry, item: create(:item, category: category))

      expect(entry.effective_pool).to be_nil
    end

    # The ownership validator guards this exact hazard; the two must not disagree about
    # whether the chain is safe to walk. Both links break the same way, so both are held.
    it "is nil rather than raising when the chain is not filled in yet", :aggregate_failures do
      expect(build(:entry, item: Item.new(name: "Unfiled")).effective_pool).to be_nil
      expect(build(:entry, item: nil).effective_pool).to be_nil
    end

    # The four examples above cover the cells where the entry has no pool of its own,
    # plus one where it does. These cover the rest of the entry-pool/category-pool/
    # default-account space so no level of the chain can silently win out of turn.
    describe "precedence between the three levels" do
      let(:savings_account) { create(:pool, :account, user: user, name: "Savings Account") }

      def entry_with(entry_pool:, category_pool:)
        category = create(:category, :expense, user: user, pool: category_pool)
        create(:entry, item: create(:item, category: category), pool: entry_pool)
      end

      it "prefers the entry's pool over both the category's pool and the default account" do
        user.update!(default_account: checking)
        entry = entry_with(entry_pool: savings_account, category_pool: groceries)

        expect(entry.effective_pool).to eq(savings_account)
      end

      it "prefers the entry's pool over the default account when the category has no pool" do
        user.update!(default_account: checking)
        entry = entry_with(entry_pool: savings_account, category_pool: nil)

        expect(entry.effective_pool).to eq(savings_account)
      end

      it "uses the entry's pool when neither the category nor the user names one" do
        entry = entry_with(entry_pool: savings_account, category_pool: nil)

        expect(entry.effective_pool).to eq(savings_account)
      end

      it "prefers the category's pool over the default account" do
        user.update!(default_account: checking)
        entry = entry_with(entry_pool: nil, category_pool: groceries)

        expect(entry.effective_pool).to eq(groceries)
      end
    end
  end

  describe "pool ownership" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    it "accepts a pool belonging to the same user" do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = build(:entry, item: create(:item, category: category), pool: checking)

      expect(entry).to be_valid
    end

    it "accepts no pool at all" do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = build(:entry, item: create(:item, category: category), pool: nil)

      expect(entry).to be_valid
    end

    # `user` resolves through item -> category, so a half-filled entry would make the
    # validator raise instead of reporting the missing item or category.
    it "reports the missing item rather than raising", :aggregate_failures do
      entry = build(:entry, item: nil, pool: checking)

      expect { entry.valid? }.not_to raise_error
      expect(entry.errors[:item]).to be_present
    end

    # With no category there is no user to compare against, so the check is skipped
    # rather than guessed at — it must not raise, and must not invent a pool error.
    it "skips the check rather than raising when the item has no category", :aggregate_failures do
      entry = build(:entry, item: Item.new(name: "Unfiled"), pool: checking)

      expect { entry.valid? }.not_to raise_error
      expect(entry.errors[:pool]).to be_empty
    end

    it "rejects a pool belonging to another user", :aggregate_failures do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = build(:entry, item: create(:item, category: category), pool: create(:pool, :account))

      expect(entry).not_to be_valid
      expect(entry.errors[:pool]).to include("must belong to the same user")
    end

    # The example above uses persisted pools, so an id comparison would satisfy it too.
    # This one holds the record comparison in place: with nothing saved, both sides'
    # `user_id` are nil, and `nil == nil` would wave the foreign pool straight through.
    it "rejects an unsaved pool owned by a different unsaved user", :aggregate_failures do
      item = Item.new(name: "Unfiled", category: Category.new(user: User.new))
      entry = build(:entry, item: item, pool: build(:pool, :account, user: User.new))

      expect(entry).not_to be_valid
      expect(entry.errors[:pool]).to include("must belong to the same user")
    end
  end

  # The mirror of Category's income rule: Entry#pool is a second channel to the same
  # destination, so income has to land in an account here too, never in an envelope.
  describe "income entries" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    def income_entry_overriding_to(pool)
      category = create(:category, :income, user: user)
      build(:entry, item: create(:item, category: category), pool: pool)
    end

    it "may override to an account pool" do
      expect(income_entry_overriding_to(checking)).to be_valid
    end

    it "may not override to a budget pool", :aggregate_failures do
      entry = income_entry_overriding_to(groceries)

      expect(entry).not_to be_valid
      expect(entry.errors[:pool]).to include("must be an account for income entries")
    end

    it "may not override to a savings pool", :aggregate_failures do
      entry = income_entry_overriding_to(create(:pool, :savings_pool, user: user, account: checking))

      expect(entry).not_to be_valid
      expect(entry.errors[:pool]).to include("must be an account for income entries")
    end

    # Pins the income? guard: without this a validator that rejected every non-account
    # override would pass every example above.
    it "does not constrain expense entries, which may override to a budget pool" do
      category = create(:category, :expense, user: user)

      expect(build(:entry, item: create(:item, category: category), pool: groceries)).to be_valid
    end
  end
end
