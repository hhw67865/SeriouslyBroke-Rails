# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:pool).optional }
    it { is_expected.to have_many(:budgets).dependent(:destroy) }
    it { is_expected.to have_many(:allocations_in).class_name("Allocation").dependent(:destroy) }
    it { is_expected.to have_many(:allocations_out).class_name("Allocation").dependent(:destroy) }
    it { is_expected.to have_many(:items).dependent(:destroy) }
    it { is_expected.to have_many(:entries).through(:items) }
    # `have_one(:budget)` IS DELETED WITH THE ASSOCIATION (plan 3, task 4). A Budget belongs to a
    # POOL; `budgets.category_id` is nil on every row and Task 6 drops the column.
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category_type) }

    # THIS PIN IS WITHDRAWN, NOT LEFT FAILING (two-ledger spec §5, Task 2). It read "when the
    # category names no pool → is refused", on plan 3 decision 3: a nil `pool_id` was documented as
    # "the user's default account", `PoolBalanceLedger::ENTRY_POOL_ID` resolved it to nowhere, and
    # such a category's spending left the pool tree while `Σ pools == bank truth` claimed otherwise.
    #
    # That hazard is a fact about a model where the POOL holds the money. The category holds it now,
    # spending that reaches no pool drains AVAILABLE by name (`CategoryLedger`), and the two shapes
    # this pin refused are shapes the app writes on purpose today — the savings categories Task 1's
    # migration minted and the categories Task 7's screens create. What survives is the half that is
    # still true: a pool NAMED here is still governed, and the reachability examples below are
    # unchanged.
    context "when the category names no pool" do
      let(:user) { create(:user) }

      it "is accepted, and holds its own money instead" do
        expect(build(:category, :expense, user: user, pool: nil)).to be_valid
      end

      it "is accepted the moment a pool is named" do
        expect(build(:category, :expense, user: user, pool: create(:pool, :account, user: user))).to be_valid
      end
    end

    describe "pool reachability (main-account spec §6)" do
      let(:user) { create(:user) }
      let(:main) { create(:pool, :account, user: user, name: "Main") }
      let(:other) { create(:pool, :account, user: user, name: "Ally") }

      before { user.update!(default_account: main) }

      it "accepts the main account and refuses any other account", :aggregate_failures do
        expect(build(:category, user: user, pool: main)).to be_valid
        refused = build(:category, user: user, pool: other)
        expect(refused).not_to be_valid
        expect(refused.errors[:pool]).to include("must be your main account or an envelope inside one")
      end

      it "refuses an envelope when the user has no main account to anchor its history" do
        envelope = create(:pool, :budget_pool, user: user, account: main)
        user.update!(default_account: nil)
        expect(build(:category, user: user, pool: envelope)).not_to be_valid
      end

      # M9 (fix round 2): THE OTHER DIRECTION of the example above — an envelope is fine the
      # moment the user HAS a main account, whichever account actually houses the envelope
      # (`other`, not `main`). Without this the pair only proves the refusal fires; this proves
      # it stops firing for exactly the reason it should.
      it "accepts an envelope once the user has a main account, wherever the envelope itself lives" do
        envelope = create(:pool, :budget_pool, user: user, account: other)
        expect(build(:category, user: user, pool: envelope)).to be_valid
      end
    end
  end

  # TWO VALUES, AND `savings: 2` IS RETIRED RATHER THAN RENUMBERED (plan 3, task 5). This is the
  # planted literal that says integer 2 is not reused: a third type added later takes 3, and this
  # example fails if anybody puts one at 2.
  describe "enums" do
    it { is_expected.to define_enum_for(:category_type).with_values(expense: 0, income: 1) }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, user: user) }
    let!(:expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:pool_covered_category) { create(:category, category_type: :expense, user: user, pool: pool) }
    let!(:income_category) { create(:category, category_type: :income, user: user) }

    describe ".expenses" do
      it "returns only expense categories" do
        expect(described_class.expenses).to contain_exactly(expense_category, pool_covered_category)
      end
    end

    describe ".incomes" do
      it "returns only income categories" do
        expect(described_class.incomes).to contain_exactly(income_category)
      end
    end

    # `.savings` IS GONE with the enum value (plan 3, task 5), and its absence is asserted rather
    # than left to a NoMethodError somebody reads as a typo.
    it "does not answer .savings at all" do
      expect(described_class).not_to respond_to(:savings)
    end

    # THE DISTRIBUTE WATERFALL'S ONE READ (two-ledger §2, Task 4). Two halves in one example
    # because a scope that got either wrong would pass a spec asserting the other:
    #
    #   WHO IS IN — holders only, which is `expense? && funded_since.present?`. The income category
    #   above and an unfunded expense one are both out, and they are out for different reasons.
    #
    #   IN WHAT ORDER — `[priority, name]`, and the tie-break is the half that goes wrong quietly.
    #   Zebra and Apple both sit at priority 1 and Zebra is created FIRST, so insertion order says
    #   [Zebra, Apple] while the rule says [Apple, Zebra]; Early at priority 0 comes ahead of both,
    #   so sorting by name alone fails as loudly as sorting by priority alone.
    it "orders the holders by priority then name and leaves everything else out" do
      early = create(:category, :expense, :funded, user: user, name: "Early", priority: 0)
      zebra = create(:category, :expense, :funded, user: user, name: "Zebra", priority: 1)
      apple = create(:category, :expense, :funded, user: user, name: "Apple", priority: 1)
      create(:category, :expense, user: user, name: "Never Funded", priority: 0)
      # PAST THE MODEL, deliberately, and the raise it steps around is half the fact: a funded
      # INCOME category is a shape `#holding_columns_are_sane` refuses, so the scope's `expenses`
      # arm is a belt over a validation rather than the only thing holding the law. It is planted
      # anyway, because a scope filtering on `funded_since` alone would pass every example that
      # only ever met the shapes the validation admits.
      create(:category, :income, user: user, name: "Pay", priority: 0)
        .update_columns(funded_since: 1.year.ago.to_date) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.where(user: user).in_fill_order).to eq([early, apple, zebra])
    end
  end

  # THE RATE DETECTOR'S POPULATION, and after plan 3 it is exactly the account-pointed set: an
  # account IS the buffer (§7.1), so an expense category pointing at one is spending nothing
  # reserves. The "no pool at all" half this predicate used to admit is not a shape any more —
  # `belongs_to :pool` refuses it — and the `#budgetable?` reader it used to diverge from is gone
  # with the category cap.
  describe "#buffer_funded?" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    it "is true for a category pointing at an account" do
      expect(create(:category, :expense, user: user, pool: checking)).to be_buffer_funded
    end

    it "is false once an envelope holds the spending" do
      expect(create(:category, :expense, user: user, pool: groceries)).not_to be_buffer_funded
    end

    it "is false for an income category, whichever pool it names" do
      expect(create(:category, :income, user: user, pool: checking)).not_to be_buffer_funded
    end
  end

  # BOTH DIRECTIONS, AND THE UNSAVED PAIR IS THE ONE THAT MATTERS. The validator compares RECORDS
  # rather than `user_id`s precisely because two unsaved records both answer nil — an id comparison
  # would call a foreign pool valid on `build` and only refuse it once both sides had been saved,
  # which is after the form has already offered it.
  describe "the pool it names belongs to its own user" do
    let(:user) { create(:user) }
    let(:stranger) { create(:user) }

    it "accepts a pool of the category's own user" do
      expect(build(:category, :expense, user: user, pool: create(:pool, :account, user: user))).to be_valid
    end

    it "refuses a pool belonging to somebody else", :aggregate_failures do
      category = build(:category, :expense, user: user, pool: create(:pool, :account, user: stranger))

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must belong to the same user")
    end

    it "refuses a foreign pool even when neither record is saved yet", :aggregate_failures do
      category = build(:category, :expense, user: build(:user), pool: build(:pool, :account, user: build(:user)))

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must belong to the same user")
    end

    # NOT A SECOND ERROR ABOUT A FIRST ONE. `belongs_to :user` already refuses a category with no
    # user; this validator stays quiet rather than adding "must belong to the same user" beside it.
    it "says nothing about ownership when there is no user to compare against", :aggregate_failures do
      category = build(:category, :expense, user: nil, pool: create(:pool, :account, user: user))

      expect(category).not_to be_valid
      expect(category.errors[:pool]).not_to include("must belong to the same user")
    end
  end

  describe "income categories" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user) }

    it "may point at an account pool" do
      expect(build(:category, :income, user: user, pool: checking)).to be_valid
    end

    it "may not point at a budget pool", :aggregate_failures do
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      category = build(:category, :income, user: user, pool: groceries)

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must be an account for income categories")
    end

    it "may not point at a savings pool", :aggregate_failures do
      vacation = create(:pool, :savings_pool, user: user, account: checking)
      category = build(:category, :income, user: user, pool: vacation)

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must be an account for income categories")
    end

    it "does not constrain expense categories, which may point at a budget pool" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)

      expect(build(:category, :expense, user: user, pool: groceries)).to be_valid
    end

    it "does not constrain expense categories, which may point at a savings goal" do
      vacation = create(:pool, :savings_pool, user: user, account: checking)

      expect(build(:category, :expense, user: user, pool: vacation)).to be_valid
    end
  end

  describe "#effective_pool" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user) }

    it "uses the category's own pool when set" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      user.update!(default_account: checking)

      expect(create(:category, :expense, user: user, pool: groceries).effective_pool).to eq(groceries)
    end

    # THE FALLBACK THIS METHOD USED TO PROMISE, NOW REFUSED — Task 8's fix round.
    #
    # `pool || user&.default_account` read well and was kept by nothing: every balance in the app
    # resolves an entry through `COALESCE(entries.pool_id, categories.pool_id)`
    # (`PoolBalanceLedger::ENTRY_POOL_ID`), which has no default account in it. Two readers of one
    # question, and `Σ pools == your bank balance` turned on which one you asked.
    #
    # Asserted in BOTH directions, which is the only way this is worth anything: the reader says
    # nil, AND the nominated account's own balance is measured and does not contain the $60. A
    # method agreeing with a ledger is a claim about the ledger, so the ledger is asked.
    it "ignores the user's default account, because the ledger does", :aggregate_failures do
      user.update!(default_account: checking)
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      category = create(:category, :expense, user: user, pool: groceries)
      create(:entry, item: create(:item, category: category), amount: 60, date: Date.current)

      expect(category.effective_pool).to eq(groceries)
      expect(groceries.calculator.balance).to eq(-60)
      expect(checking.calculator.balance).to eq(0)
    end

    it "uses the category's own pool when the user has no default account" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)

      expect(create(:category, :expense, user: user, pool: groceries).effective_pool).to eq(groceries)
    end

    # Matches the guard Entry#effective_pool needs on its own link in the chain.
    it "is nil rather than raising when the category has no user" do
      expect(described_class.new(name: "Unfiled").effective_pool).to be_nil
    end
  end
end
