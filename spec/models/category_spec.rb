# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:budgets).dependent(:destroy) }
    # `allocations_in` AND `allocations_out` ARE DELETED WITH THE TABLE (computed-claims spec §5).
    # Both were `dependent: :destroy` so that destroying a category that had ever held money did not
    # raise on a foreign key with no ON DELETE. Nothing moves on the purpose side any more: a
    # category's money is `#claim`, so there is no row to cascade. What a destroyed category still
    # takes with it is its rules (`have_many(:budgets).dependent(:destroy)` above) and, through them,
    # their adjustments.
    it { is_expected.to have_many(:items).dependent(:destroy) }
    it { is_expected.to have_many(:entries).through(:items) }
    # `belongs_to(:pool)` IS DELETED WITH `categories.pool_id` (two-ledger spec §5, Task 8) — a
    # category holds its own money and names no lane. `have_one(:budget)` went in plan 3 task 4.
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category_type) }
  end

  # ** A CATEGORY'S MONEY IS THE SUM OF ITS RULES' CLAIMS AND NOTHING ELSE (computed-claims spec
  # §2). ** Nothing was moved to put it there, so a category with no rules claims nothing however
  # much has been spent against it — §3.4's unbudgeted row shows `spent $X`, which is a fact about
  # entries rather than a claim.
  describe "#claim" do
    let(:user) { create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1)) }
    let(:groceries) { create(:category, :expense, user: user, name: "Groceries", funded_since: Date.new(2026, 1, 1)) }

    # ONE CATCH-ALL RULE AND ONE ITEM-BACKED ONE, which is the only way a category carries two:
    # `Budget#category_may_hold_one_item_less_rule` refuses a second rule whose lane is the whole
    # category, precisely because their claims would both subtract the same entries.
    it "adds up every rule it carries" do
      create(:budget, :per_period_rate, category: groceries, amount: 400)
      create(
        :budget,
        :per_period_rate,
        category: groceries,
        amount: 75,
        item: create(:item, category: groceries, name: "Coffee")
      )

      expect(groceries.claim(today: Date.new(2026, 9, 3))).to eq(475)
    end

    it "claims nothing at all when no rule names it" do
      create(:entry, item: create(:item, category: groceries), amount: 250, date: Date.new(2026, 9, 2))

      expect(groceries.claim(today: Date.new(2026, 9, 3))).to eq(0)
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
    let!(:expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:second_expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:income_category) { create(:category, category_type: :income, user: user) }

    describe ".expenses" do
      it "returns only expense categories" do
        expect(described_class.expenses).to contain_exactly(expense_category, second_expense_category)
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

  # FIVE BLOCKS ARE DELETED HERE, ALL ABOUT `categories.pool_id` (two-ledger spec §5, Task 8):
  # `#buffer_funded?` (the rate detector's population, re-aimed at `#holder?` in Task 7),
  # `#effective_pool` and its default-account fallback, the pool-ownership pair, the reachability
  # rules, and the income-lands-in-an-account rule. Every one of them answered "where does this
  # category's spending LAND", which is the pool era's question; the two-ledger answer is
  # `#holder?` and `funded_since`, pinned in `spec/models/category_holdings_spec.rb`.
end
