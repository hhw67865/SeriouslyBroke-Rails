# frozen_string_literal: true

require "rails_helper"

# CATEGORIES HOLD THE MONEY (two-ledger spec §3): the columns that make one a holder, the three
# predicates read off them, and the associations that die with it.
RSpec.describe "Category, as a holder of money", type: :model do
  let(:user) { create(:user) }

  # The account every category in this file points at while `categories.pool_id` still exists —
  # referenced by nothing, which is the point: it is the user's MAIN account, and the category
  # factory reaches for `user.default_account` when a spec does not name a pool.
  before { create(:pool, :account, user: user, name: "Checking") }

  describe "#holder?" do
    it "is a funded expense category, and nothing else", :aggregate_failures do
      expect(create(:category, :expense, :funded, user: user, name: "Food")).to be_holder
      expect(create(:category, :expense, user: user, name: "Misc")).not_to be_holder
      # Past the model on purpose: #only_expenses_hold_money refuses this shape, and the predicate
      # has to answer for the row anyway — it is the one thing standing between an income
      # category and a holding.
      income = build(:category, :income, user: user, name: "Pay", funded_since: Date.new(2026, 1, 1))
      income.save!(validate: false)

      expect(income).not_to be_holder
    end
  end

  describe "#savings?" do
    # THE SHAPE TASK 1'S MIGRATION MINTS: a goal folded out of a savings pool carries a target, a
    # `funded_since`, `tracked: false` and NO rule. Nothing else in the app writes it, and every
    # screen that used to ask `pool.pool_type_savings?` asks this instead.
    it "is a funded category with a target and no rule" do
      goal = create(:category, :expense, :savings, user: user, name: "House", tracked: false)

      expect(goal).to be_savings
    end

    it "is not a category with a target that is also driven by a rule" do
      goal = create(:category, :expense, :savings, user: user, name: "House")
      create(:budget, :category_rule, category: goal)

      expect(goal.reload).not_to be_savings
    end

    it "is not a category with no target at all" do
      expect(create(:category, :expense, :funded, user: user, name: "Food")).not_to be_savings
    end

    it "is not an unfunded category carrying a target" do
      dormant = create(:category, :expense, user: user, name: "Someday", target_amount: 500)

      expect(dormant).not_to be_savings
    end
  end

  # THE RUBY MIRROR OF `CategoryLedger::ENTRY_CATEGORY_ID`, and the only one there is: spending
  # counts against a category from `funded_since` onward, in the OWNER's day.
  describe "#counts_spending_on?" do
    let(:food) { create(:category, :expense, user: user, name: "Food", funded_since: Date.new(2026, 8, 1)) }

    it "counts the funding day itself and every day after it", :aggregate_failures do
      expect(food.counts_spending_on?(Date.new(2026, 8, 1))).to be(true)
      expect(food.counts_spending_on?(Date.new(2026, 9, 30))).to be(true)
    end

    it "does not count the day before" do
      expect(food.counts_spending_on?(Date.new(2026, 7, 31))).to be(false)
    end

    it "never counts spending on a category that was never funded" do
      misc = create(:category, :expense, user: user, name: "Misc")

      expect(misc.counts_spending_on?(Date.current)).to be(false)
    end

    # BOTH SIDES OF ONE MIDNIGHT, an hour apart: 15:00 UTC is Tokyo's Aug 1 and counts, 14:00 UTC
    # is still Tokyo's Jul 31 and does not. The SQL half of this rule is pinned the same way in
    # spec/services/category_ledger_spec.rb, over the same two instants.
    it "reads an instant in the owner's own timezone rather than UTC", :aggregate_failures do
      user.update!(timezone: "Asia/Tokyo")

      expect(food.reload.counts_spending_on?(Time.utc(2026, 7, 31, 15, 0))).to be(true)
      expect(food.counts_spending_on?(Time.utc(2026, 7, 31, 14, 0))).to be(false)
    end
  end

  # THE NIL POOL, EXPRESSIBLE AGAIN AND ANSWERING THE OPPOSITE OF WHAT IT ONCE DID. Before the
  # cutover a pool-less category WAS the buffer-funded shape; a category holds its own money now, so
  # it is the one shape this predicate must say is not coming out of the buffer. Both directions,
  # and the pool-less half is planted through `create` rather than past the model — that it saves at
  # all is half the fact under test.
  describe "#buffer_funded?" do
    it "is false for a category that names no pool" do
      expect(create(:category, :expense, user: user, name: "Holder", pool: nil)).not_to be_buffer_funded
    end

    it "is still true for an expense category pointing at an account" do
      expect(create(:category, :expense, user: user, name: "Misc")).to be_buffer_funded
    end
  end

  describe "the columns" do
    it "refuses a negative priority" do
      expect(build(:category, :expense, user: user, priority: -1)).not_to be_valid
    end

    it "refuses a target of zero or less", :aggregate_failures do
      expect(build(:category, :expense, user: user, target_amount: 0)).not_to be_valid
      expect(build(:category, :expense, user: user, target_amount: -1)).not_to be_valid
    end

    it "refuses money-holding columns on an income category", :aggregate_failures do
      record = build(:category, :income, user: user, funded_since: Date.current, target_amount: 100)

      expect(record).not_to be_valid
      expect(record.errors[:base]).to include("only expense categories hold money")
    end
  end

  describe "what dies with the category" do
    let(:food) { create(:category, :expense, :funded, user: user, name: "Food") }

    it "takes its rules with it" do
      create(:budget, :category_rule, category: food)

      expect { food.destroy }.to change(Budget, :count).by(-1)
    end

    it "takes the allocations on both of its sides with it" do
      create(:allocation, to_category: food)
      create(:allocation, from_category: food)

      expect { food.destroy }.to change(Allocation, :count).by(-2)
    end

    # `allocations` has real foreign keys to `categories` with no ON DELETE, so a user whose
    # categories hold money is destroyable only because both sides are `dependent: :destroy`.
    it "lets the whole user go" do
      create(:allocation, to_category: food)

      expect { user.destroy }.to change(Allocation, :count).by(-1)
    end
  end
end
