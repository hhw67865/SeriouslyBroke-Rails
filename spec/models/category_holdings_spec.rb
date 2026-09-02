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

  # `#buffer_funded?` IS DELETED WITH `categories.pool_id` (two-ledger spec §5, Task 8), and with
  # it the two examples that stood here. It asked which POOL a category's spending came out of; the
  # question the app asks now is `#holder?`, above — a category either holds its own money from
  # `funded_since` on or its spending drains available.

  describe "the columns" do
    it "refuses a negative priority" do
      expect(build(:category, :expense, user: user, priority: -1)).not_to be_valid
    end

    it "refuses a target of zero or less", :aggregate_failures do
      expect(build(:category, :expense, user: user, target_amount: 0)).not_to be_valid
      expect(build(:category, :expense, user: user, target_amount: -1)).not_to be_valid
    end

    # ** A FUTURE FUNDING START IS REFUSED (fix round 1, LOW-1). ** Every reader treats "set" as
    # "counting now" — `Category#holder?` asks only that the column is present, so a future-dated
    # category joins the fill order and a distribution funds it TODAY, while
    # `CategoryLedger::ENTRY_CATEGORY_ID` goes on reading its spending against AVAILABLE until the
    # date arrives. Money in, spending out of the root, and no screen saying why. Nothing in this
    # app schedules, so the shape is refused rather than coerced.
    #
    # BOTH DIRECTIONS, and TODAY is the half that matters most: a category funded this morning
    # counts this morning's spending, which is the ordinary shape of setting one — a validator that
    # refused it would break every "give this category a start date" flow in the app.
    it "accepts today as a funding start" do
      expect(build(:category, :expense, user: user, funded_since: Date.current)).to be_valid
    end

    it "refuses a funding start in the future", :aggregate_failures do
      record = build(:category, :expense, user: user, funded_since: Date.current + 1.day)

      expect(record).not_to be_valid
      expect(record.errors[:funded_since].to_sentence).to include("can't be in the future")
    end

    it "refuses money-holding columns on an income category", :aggregate_failures do
      record = build(:category, :income, user: user, funded_since: Date.current, target_amount: 100)

      expect(record).not_to be_valid
      expect(record.errors[:base]).to include("only expense categories hold money")
    end
  end

  # ** MOVING THE FUNDING START EARLIER CHANGES WHAT THE CATEGORY HOLDS (fix round 1, LOW-2). **
  #
  # This is the promise the category form's hint makes — *"Spending before it reads against what's
  # available instead — so changing this date moves history"* — and it is the whole reason the field
  # is editable at all (spec §4). `CategoryLedger::ENTRY_CATEGORY_ID` compares every entry's date
  # against this column, so the SAME entry drains the category on one side of the move and AVAILABLE
  # on the other. Nothing is rewritten; one date is, and the ledger re-reads.
  #
  # PLANTED LITERALS ON BOTH SIDES, and both halves of the partition asserted at once: §2's
  # invariant is `available + Σ holdings == income − expenses`, so the $80 the category takes on has
  # to be $80 the root gives up. A test that watched only the holding would pass against a reader
  # that had started counting the entry twice.
  describe "moving the funding start" do
    it "hands a pre-existing entry to the category, and takes it off available", :aggregate_failures do
      groceries = planted_history

      expect(ledger_for(groceries)).to eq(holding: 200, available: 220)

      groceries.update!(funded_since: Date.current - 45.days)

      expect(ledger_for(groceries)).to eq(holding: 120, available: 300)
    end

    # $500 of income, $200 allocated into Groceries, and an $80 shop dated BEFORE the funding start
    # — so it drains available while the start stands where it is.
    def planted_history
      groceries = create(
        :category,
        :expense,
        user: user,
        name: "Groceries",
        funded_since: Date.current - 10.days
      )
      income(500, on: Date.current - 40.days)
      create(:allocation, kind: :allocation, to_category: groceries, amount: 200, date: Date.current)
      spend(groceries, 80, on: Date.current - 30.days)
      groceries
    end

    def income(amount, on:)
      salary = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: salary), amount: amount, date: on)
    end

    def spend(category, amount, on:)
      item = create(:item, category: category, name: "Weekly shop")
      create(:entry, item: item, amount: amount, date: on)
    end

    # A FRESH LEDGER EACH TIME, never a memoised one: `CategoryLedger` snapshots its grouped queries
    # at first read, so reusing one across the write would answer from before it.
    def ledger_for(category)
      ledger = CategoryLedger.new([category], user: user)
      { holding: ledger.holding_of(category), available: ledger.available }
    end
  end

  # ** THE STAMP THAT STARTS THE CLOCK, SPELLED ONCE (final fix wave, I-1). ** §4 names TWO events —
  # "the date it first got a rule OR AN ALLOCATION" — and only the rule half was ever written.
  # `BudgetProposal` and `AllocationsController` both come here now, so the rule cannot drift into two
  # answers about when a category starts holding.
  describe "#start_holding" do
    let(:misc) { create(:category, :expense, user: user, name: "Misc") }

    it "stamps today on a category that was not holding money yet", :aggregate_failures do
      expect(misc.start_holding).to be(true)
      expect(misc.reload.funded_since).to eq(Date.current)
      expect(misc).to be_holder
    end

    # THE OTHER DIRECTION, AND IT IS THE ONE WITH TEETH: re-stamping a category that is already
    # holding would push its start date FORWARD and hand its own recent spending back to available.
    # The second rule in a category, and every allocation after the first, take this arm.
    it "leaves a category that is already holding exactly where it is", :aggregate_failures do
      food = create(:category, :expense, user: user, name: "Food", funded_since: Date.current - 90.days)

      expect(food.start_holding).to be(true)
      expect(food.reload.funded_since).to eq(Date.current - 90.days)
    end

    # A caller may name the day; `Date.current` is only the default. The refusal below is the future
    # validator's, reached through this writer — which is what keeps the stamp from being a way past
    # the model.
    it "refuses a day the category may not start on, and says so on the record", :aggregate_failures do
      expect(misc.start_holding(today: Date.current + 1.day)).to be(false)
      expect(misc.errors[:funded_since].to_sentence).to include("can't be in the future")
      expect(misc.reload.funded_since).to be_nil
    end
  end

  # ** MONEY MAY NOT BE LEFT IN A CATEGORY THAT NO LONGER HOLDS (final fix wave, I-1). ** The
  # form-reachable half of the stranding pair: `funded_since` is user-editable, and clearing it on a
  # category carrying allocations left the money exactly where it was while every reader stopped
  # looking — absent from `Category.in_fill_order` and from every holder population, its show page
  # headlining "doesn't hold money yet" over the balance, and no picker offering to move it back out.
  #
  # BOTH DIRECTIONS, and the second is the one that keeps the guard from being a lock: a category
  # that holds nothing clears freely, which is the ordinary "I set this up by mistake" flow the form's
  # hint has always promised.
  describe "clearing the funding start" do
    let(:groceries) do
      create(:category, :expense, user: user, name: "Groceries", funded_since: Date.current - 10.days)
    end

    it "is refused while the category still holds money, and names the figure", :aggregate_failures do
      create(:allocation, to_category: groceries, amount: 400, date: Date.current)

      groceries.funded_since = nil

      expect(groceries).not_to be_valid
      expect(groceries.errors[:funded_since].to_sentence)
        .to eq("can't be cleared while this category still holds $400.00 — move the money out first")
      expect(groceries.reload.funded_since).to eq(Date.current - 10.days)
    end

    it "is allowed on a category that holds nothing", :aggregate_failures do
      expect(groceries.update(funded_since: nil)).to be(true)
      expect(groceries.reload.funded_since).to be_nil
    end

    # SPENDING IS PART OF THE FIGURE, which is why the guard reads the LEDGER rather than asking
    # whether any allocations exist: $400 in and $400 out is a category holding nothing, and refusing
    # that clear would be a lock on a category with no money in it. The entry is dated after the
    # funding start, so `CategoryLedger::ENTRY_CATEGORY_ID` attributes it here.
    it "is allowed once the money that came in has been spent", :aggregate_failures do
      create(:allocation, to_category: groceries, amount: 400, date: Date.current)
      item = create(:item, category: groceries, name: "Weekly shop")
      create(:entry, item: item, amount: 400, date: Date.current - 1.day)

      expect(groceries.update(funded_since: nil)).to be(true)
      expect(groceries.reload.funded_since).to be_nil
    end

    # A MOVE BACK OUT IS THE DOOR THE MESSAGE NAMES, so it has to actually open the lock. The
    # withdrawal is the `category → available` row `/allocations/new` writes.
    it "is allowed once the money has been moved back to available", :aggregate_failures do
      create(:allocation, to_category: groceries, amount: 400, date: Date.current)
      create(:allocation, from_category: groceries, to_category: nil, amount: 400, date: Date.current)

      expect(groceries.update(funded_since: nil)).to be(true)
      expect(groceries.reload.funded_since).to be_nil
    end

    # THE GUARD IS ABOUT CLEARING, NOT ABOUT HOLDING MONEY. A funded category with a balance must
    # still be editable in every other respect, or the guard would have made a holder read-only.
    it "leaves every other edit on a category that holds money alone", :aggregate_failures do
      create(:allocation, to_category: groceries, amount: 400, date: Date.current)

      expect(groceries.update(name: "Food & Grocery", funded_since: Date.current - 20.days)).to be(true)
      expect(groceries.reload.funded_since).to eq(Date.current - 20.days)
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
