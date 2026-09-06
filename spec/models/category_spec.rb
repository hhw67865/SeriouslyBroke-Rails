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

    # ** AN OPENING CATEGORY IS NOT SPENDING (fix round — MED-2). ** `Opening Shortfall` is an
    # EXPENSE by construction — that is how a negative opening lowers the pot — so every screen that
    # asked `.expenses` for "what this household spends on" was answering with bookkeeping. Both
    # directions in one example each, because a scope that returned the wrong half would pass an
    # assertion about membership alone.
    describe ".opening and .spendable" do
      let!(:opening_balance) { create(:category, :income, user: user, name: Category::OPENING_BALANCE_NAME) }
      let!(:opening_shortfall) { create(:category, :expense, user: user, name: Category::OPENING_SHORTFALL_NAME) }

      it "answers both opening names and nothing else" do
        expect(described_class.where(user: user).opening).to contain_exactly(opening_balance, opening_shortfall)
      end

      # CASE-INSENSITIVE, matching `Category`'s own uniqueness validation: a user who typed
      # "opening shortfall" into the ordinary categories screen owns the same row `AccountOpening`
      # would have found, and the two must not disagree about it.
      it "matches a name the user typed in another case" do
        theirs = create(:category, :expense, user: create(:user), name: "opening shortfall")

        expect(described_class.opening).to include(theirs)
      end

      it "leaves both out of the spendable expenses, and keeps the real ones", :aggregate_failures do
        expect(described_class.where(user: user).spendable)
          .to contain_exactly(expense_category, second_expense_category)
        expect(described_class.where(user: user).spendable).not_to include(opening_shortfall)
      end

      # ** THE CATEGORIES INDEX STILL LISTS BOTH, AND THAT IS THE RULING RATHER THAN AN OVERSIGHT
      # (fix round — MED-2). ** `#with_type` is that screen's reader, and that screen is where a
      # category is renamed or deleted — which is the user's own escape hatch for a mistyped opening
      # figure, stated at `OPENING_NAMES` and inherited from the deleted opening-balance controller.
      # Narrowing it would leave `Opening Shortfall` a category its owner could neither see nor
      # remove. The ENTRIES screen's expenses tab is where MED-2's fourth leak was closed, by the
      # marker column, and `spec/requests/entries_spec.rb` pins it.
      it "still offers both to the categories index, where they can be renamed", :aggregate_failures do
        expect(described_class.where(user: user).with_type(:expense)).to include(opening_shortfall)
        expect(described_class.where(user: user).with_type(:income)).to include(opening_balance)
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

  # ** THE ONE KEY A CATEGORY'S RULES ARE LISTED BY (fix wave — LOW-3). ** Three screens render §3.4's
  # line per rule — Home's period row, the Budget page's group and the category card — and each had
  # written the key itself; two agreed and Home did not, so one category's rules read one way on Home
  # and another two clicks along. Every term is asserted in both directions here, because a key is
  # exactly the kind of thing that passes its callers' examples while being wrong in one place.
  describe ".rule_order" do
    def key(due, amount, id) = described_class.rule_order(next_due_on: due, amount: amount, id: id)

    # `<=>` RATHER THAN `be <`: the key is an Array, which defines the spaceship but not `<`.
    def before?(one, other) = (one <=> other).negative?

    # TERM 1: a rule with a date sorts ahead of one without. A rate rule is never due, and "what is
    # coming" is what a reader scanning the list is after. The undated rule is given the LARGER
    # amount, so a key that had dropped this term would order them the other way round.
    it "puts a dated rule ahead of an undated one", :aggregate_failures do
      expect(before?(key(Date.new(2026, 6, 1), 100, 1), key(nil, 9_999, 0))).to be(true)
      expect(before?(key(nil, 9_999, 0), key(Date.new(2099, 1, 1), 100, 1))).to be(false)
    end

    # TERM 2: among dated rules the earlier date leads.
    it "puts the earlier due date first", :aggregate_failures do
      expect(before?(key(Date.new(2026, 2, 14), 100, 2), key(Date.new(2026, 6, 1), 100, 1))).to be(true)
      expect(before?(key(Date.new(2026, 6, 1), 100, 1), key(Date.new(2026, 2, 14), 100, 2))).to be(false)
    end

    # TERM 3: a shared date breaks toward the LARGER obligation — the bigger bill is the one you can
    # least afford to be short on. Asserted with the amount as an Integer on one side and a
    # BigDecimal on the other, which is the mix an in-memory record produces and which the key's
    # `.to_d` exists for.
    it "breaks a shared date toward the larger amount", :aggregate_failures do
      due = Date.new(2026, 6, 1)

      expect(before?(key(due, 500, 9), key(due, BigDecimal("180"), 1))).to be(true)
      expect(before?(key(due, BigDecimal("180"), 1), key(due, 500, 9))).to be(false)
    end

    # TERM 4: identical rules stay put. `budgets` carries no ORDER BY and a plain UPDATE relocates a
    # row in the heap, so without this two rules could swap between page loads with no data change.
    # Both arms, because the undated lane reaches the tie-break through `NEVER_DUE`.
    it "breaks an identical pair on the id", :aggregate_failures do
      due = Date.new(2026, 6, 1)

      expect(before?(key(due, 100, 1), key(due, 100, 2))).to be(true)
      expect(before?(key(nil, 100, 1), key(nil, 100, 2))).to be(true)
    end
  end

  # ** `#building_rule` AND `.fund_is_the_whole_category?` ARE DELETED WITH THE SHAPE (two-shapes
  # spec §7), AND SO IS EVERY EXAMPLE THAT PINNED THEM. **
  #
  # The first found the item-less rule whose unspent money survived the period boundary — the
  # category's fund — and the second asked whether that fund was the category's ONLY rule, which was
  # the gate on every "of $X" and every bar drawn against a target. Both questions were about
  # `budgets.carries_over`, which `TwoShapes` drops. A fund is a dated rule now, its ceiling is its
  # own `amount`, and its progress is one rule's two figures rather than a category-level Σ measured
  # against one rule's target — so there is nothing for either reader to answer.
  #
  # WHERE EACH CALLER WENT, so a later reader can find the successors:
  #
  #   the dashboard's Savings band  → `Budget.saving_toward_a_date`, pinned in `budget_spec`
  #   `CategoryBudgetPresenter`     → `#fund_line` over the rows its page's ledger already fetched
  #   the entry form's impact card  → its own calculator's `#dated?` and `#target`, with the
  #                                   sole-rule guard kept for its own (unchanged) measured reason

  # FIVE BLOCKS ARE DELETED HERE, ALL ABOUT `categories.pool_id` (two-ledger spec §5, Task 8):
  # `#buffer_funded?` (the rate detector's population, re-aimed at `#holder?` in Task 7),
  # `#effective_pool` and its default-account fallback, the pool-ownership pair, the reachability
  # rules, and the income-lands-in-an-account rule. Every one of them answered "where does this
  # category's spending LAND", which is the pool era's question; the two-ledger answer is
  # `#holder?` and `funded_since`, pinned in `spec/models/category_holdings_spec.rb`.
end
