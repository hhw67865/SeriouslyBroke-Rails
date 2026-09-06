# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:item).optional }

    # `belongs_to(:pool)` IS DELETED WITH `budgets.pool_id` (two-ledger spec §5, Task 8). A rule
    # belongs to the category that holds the money, and that is the only owner there is.
    #
    # `optional` AT THE ASSOCIATION LEVEL, required by `#must_have_a_category` — so an owner-less
    # rule reports on `:base` ("must belong to a category"), which is where the form renders it,
    # rather than as "Category must exist" against a picker the form re-renders empty. The gate is
    # also what lets two migration specs plant rules against a schema rewound past the column.
    it { is_expected.to belong_to(:category).optional }

    # THE DATED, SIGNED DELTAS ON THIS RULE'S ACCRUAL (computed-claims spec §3.3). `dependent:
    # :destroy` because a delta with no accrual to be a delta ON is a claim with no arm to land on.
    it { is_expected.to have_many(:adjustments).dependent(:destroy) }
  end

  # THE ONE DOOR ONTO WHAT THIS RULE CLAIMS (computed-claims spec §3), and the port of
  # `Category#holding_calculator`'s role: the keywords thread through and default to nothing, so a
  # caller that batches and a caller that does not are on the same object.
  describe "#claim_calculator" do
    it "hands back a calculator for this rule on the day it was asked about", :aggregate_failures do
      rule = create(:budget, :per_period_rate, amount: 400)
      calculator = rule.claim_calculator(today: Date.new(2026, 9, 3))

      expect(calculator).to be_a(ClaimCalculator)
      expect(calculator.claim).to eq(400)
    end

    it "reads the rows it is handed rather than the database" do
      rule = create(:budget, :per_period_rate, amount: 400)

      expect(rule.claim_calculator(today: Date.new(2026, 9, 3), spending: [[Date.new(2026, 9, 2), 150.to_d]]).claim)
        .to eq(250)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }

    # A negative amount is not merely wrong-looking: PoolCalculator's waterfall does
    # `remaining.clamp(0, budget.amount)`, and `clamp(0, negative)` raises. A zero amount
    # is a rule that demands nothing, which is what deleting it is for.
    describe "amount sign" do
      it "rejects a negative amount", :aggregate_failures do
        budget = build(:budget, amount: -50)

        expect(budget).not_to be_valid
        expect(budget.errors[:amount]).to include("must be greater than 0")
      end

      it "rejects a zero amount" do
        expect(build(:budget, amount: 0)).not_to be_valid
      end
    end

    # ** ZERO IS LEGAL FOR NO SHAPE AT ALL (two-shapes spec §2, Henry's ruling of 2026-09-05). **
    #
    # ** THE "set-aside-only goal" GROUP IS DELETED WITH THE EXEMPTION (§7). ** It was the one shape
    # `Budget#set_aside_only?` let past `amount > 0`: a goal fed only by hand, whose "no standing
    # rate" was spelled as an amount of ZERO because there was no deadline for a rate to be derived
    # from. A goal names a DAY now, so its per-period share is `remaining ÷ periods until the date`
    # and its amount IS the target — there is nothing left for a zero to mean, and `TwoShapes`
    # converted every such row.
    #
    # ** AND THE "money that builds up" GROUP GOES WITH THE COLUMNS IT REFEREED. ** It pinned both
    # halves of `#build_up_must_be_valid` — a dated rule may not also carry over, and a cap may not
    # sit on money that resets — plus the positive-target rule. All three are about
    # `budgets.carries_over` and `budgets.target_amount`, which `TwoShapes` drops. What is left is one
    # sentence about the amount, asserted in both directions on every shape the app still has, so a
    # validation that quietly stopped firing on one of them would fail here.
    describe "the amount" do
      let(:owner) { create(:category, :expense, :funded) }

      it "refuses zero on a per-period rule" do
        expect(build(:budget, :per_period_rate, category: owner, amount: 0)).not_to be_valid
      end

      it "refuses zero on an anchorless monthly rule" do
        expect(build(:budget, :rate, category: owner, amount: 0)).not_to be_valid
      end

      it "refuses zero on a dated rule" do
        expect(build(:budget, :by_date, category: owner, amount: 0)).not_to be_valid
      end

      it "refuses a negative amount" do
        expect(build(:budget, :by_date, category: owner, amount: -1)).not_to be_valid
      end

      # THE POSITIVE TWIN OF ALL FOUR, because a validation asserted only where it fires says nothing
      # about what it lets through.
      it "accepts a positive amount on every shape", :aggregate_failures do
        expect(build(:budget, :per_period_rate, category: owner, amount: 400)).to be_valid
        expect(build(:budget, :rate, category: create(:category, :expense, :funded), amount: 260)).to be_valid
        expect(build(:budget, :by_date, category: create(:category, :expense, :funded), amount: 5_000)).to be_valid
      end
    end
  end

  # ** EVERY RULE HAS A TYPE (spec §3): bill, usage or choice. ** The enum's integers are asserted
  # because they are stored, and the give-way RANK is asserted separately because it is deliberately
  # NOT the enum's order — money gives way in the order a person would sacrifice it, which is the
  # reverse of how urgent it is.
  describe "#rule_type" do
    it "stores the three types as 0, 1 and 2", :aggregate_failures do
      expect(described_class.rule_types).to eq("bill" => 0, "usage" => 1, "choice" => 2)
    end

    it "answers a predicate for each", :aggregate_failures do
      expect(build(:budget, :bill)).to be_bill
      expect(build(:budget, :usage)).to be_usage
      expect(build(:budget, :choice)).to be_choice
      expect(build(:budget, :bill)).not_to be_choice
    end

    # THE DEFAULT IS `usage`, and it is a ruling rather than an accident (§6 step 3): it is the
    # widest of the three, so a rule nobody has typed claims neither that it must be paid nor that
    # it is discretionary.
    it "types a rule nobody has typed as usage" do
      expect(build(:budget).rule_type).to eq("usage")
    end

    it "refuses a rule with no type at all", :aggregate_failures do
      rule = build(:budget, rule_type: nil)

      expect(rule).not_to be_valid
      expect(rule.errors[:rule_type]).to include("can't be blank")
    end

    # ** CHOICE FIRST, THEN USAGE, THEN BILL (§3's give-way order). ** Spelled ONCE, here, because
    # the Budget page's reorder copy and the walk that lists uncovered claims both read it and two
    # spellings is how a screen and a walk come to disagree about which rule gives way. The rank is
    # asserted as an ORDER as well as three numbers, so renumbering it consistently still passes and
    # reversing it does not.
    it "ranks choice ahead of usage ahead of bill", :aggregate_failures do
      expect(described_class::TYPE_RANK).to eq(choice: 0, usage: 1, bill: 2)
      expect(build(:budget, :choice).type_rank).to eq(0)
      expect(build(:budget, :usage).type_rank).to eq(1)
      expect(build(:budget, :bill).type_rank).to eq(2)
    end

    it "sorts a mixed set of rules into give-way order" do
      rules = [build(:budget, :bill), build(:budget, :choice), build(:budget, :usage)]

      expect(rules.sort_by(&:type_rank).map(&:rule_type)).to eq(["choice", "usage", "bill"])
    end
  end

  # ** WHICH CATEGORIES ARE SAVING TOWARD A DAY (two-shapes spec §2/§7) — ONE SCOPE, AND ONE ONLY. **
  #
  # ** IT WAS `BUILDS_UP_THE_CATEGORY` AND A PAIR OF DERIVED READERS. ** The hash was
  # `item_id: nil, carries_over: true` and it had two spellings — a scope for the dashboard's
  # `IN (SELECT category_id …)` subquery and a predicate for rows already loaded — which this group
  # pinned equal over all four combinations of the two clauses. Both columns are dropped, and the
  # question is a different one: what the Savings band is about is a target with a DAY on it, which
  # is an anchor with NO interval (§2's row 5) that the user did not call a `bill`. A rule that
  # REPEATS is a recurring bill, and so is a one-off the user typed as one.
  #
  # ** THE TWIN CAME BACK, AND SO DOES THE EQUALITY (fix wave — MED-2). ** This note said "ONE SCOPE
  # AND NO IN-MEMORY TWIN, so there is no equality left to pin" while TWO readers were spelling the
  # four clauses out in Ruby — `Dashboard::OverviewPresenter` and `CategoryBudgetPresenter`, both of
  # them asked of rows already loaded, where the relation would cost a statement per card. So the
  # predicate is necessary; three spellings of it were not. `Budget::SAVING_TOWARD_A_DATE` and its
  # negative half derive the scope AND `#saving_toward_a_date?`, and this group pins them equal over
  # every clause combination again, exactly as `BUILDS_UP_THE_CATEGORY`'s did.
  describe "the categories saving toward a day" do
    let(:groceries) { create(:category, :expense, :funded, name: "Groceries") }

    def lane(name) = create(:item, category: groceries, name: name)

    def holder(name) = create(:category, :expense, :funded, name: name)

    # ONE ITEM-LESS RULE PER CATEGORY (`#category_may_hold_one_item_less_rule`), so the three
    # item-less fixtures take a category each.
    def planted
      {
        one_off: create(:budget, :by_date, :choice, category: groceries, amount: 5_000),
        bill_one_off: create(:budget, :by_date, :bill, category: holder("Tax Estimate"), amount: 3_000),
        item_backed_one_off: create(:budget, :by_date, category: groceries, amount: 900, item: lane("Flights")),
        repeating: create(:budget, :recurring, category: holder("Insurance"), amount: 600),
        resetting: create(:budget, :per_period_rate, category: holder("Fun"), amount: 400)
      }
    end

    # ONE OF EACH WAY TO FAIL THE FOUR CLAUSES: a rule that repeats is a recurring bill, a rate rule
    # saves toward nothing, an item-backed one speaks for one item's spending rather than for the
    # category (§3.1's partition — the clause the retired pair carried, asked of the new columns),
    # and a rule the user typed `bill` is a thing that must be PAID rather than a thing being saved
    # for (fix round 1 — LOW-7).
    it "selects the item-less, non-bill, one-off dated rules and nothing else", :aggregate_failures do
      rules = planted

      expect(described_class.saving_toward_a_date.to_a).to eq([rules.fetch(:one_off)])
      expect(described_class.saving_toward_a_date).not_to include(rules.fetch(:bill_one_off))
      expect(described_class.saving_toward_a_date).not_to include(rules.fetch(:item_backed_one_off))
      expect(described_class.saving_toward_a_date).not_to include(rules.fetch(:repeating))
      expect(described_class.saving_toward_a_date).not_to include(rules.fetch(:resetting))
    end

    # ** THE SCOPE AND THE PREDICATE, EQUAL OVER EVERY COMBINATION (fix wave — MED-2). ** Two
    # spellings of one question are two answers waiting to happen, and the ones that had drifted were
    # in Ruby: the presenters' twins read raw columns while the scope read `rule_type` as an enum.
    # The whole planted set is walked, so each of the four clauses is exercised in both directions on
    # the same row — a predicate that dropped the `bill` clause, or the `item_id` one, disagrees here
    # rather than on a screen.
    it "answers the same in Ruby as in SQL, row by row", :aggregate_failures do
      rules = planted
      selected = described_class.saving_toward_a_date.to_a

      expect(rules.values.select(&:saving_toward_a_date?)).to eq(selected)
      expect(rules.fetch(:one_off)).to be_saving_toward_a_date
      expect(rules.fetch(:bill_one_off)).not_to be_saving_toward_a_date
      expect(rules.fetch(:item_backed_one_off)).not_to be_saving_toward_a_date
      expect(rules.fetch(:repeating)).not_to be_saving_toward_a_date
      expect(rules.fetch(:resetting)).not_to be_saving_toward_a_date
    end

    # THE PREDICATE ANSWERS BEFORE THERE IS A ROW TO SELECT, which is half of why it exists: it is
    # asked of records a caller holds, and an unsaved one is the sharpest version of that.
    it "answers on a rule that has never been saved", :aggregate_failures do
      expect(build(:budget, :by_date, :choice, category: groceries, amount: 5_000)).to be_saving_toward_a_date
      expect(build(:budget, :by_date, :bill, category: groceries, amount: 5_000)).not_to be_saving_toward_a_date
    end

    # ** THE `bill` CLAUSE ON ITS OWN, BOTH DIRECTIONS, ON ONE PAIR OF ROWS THAT DIFFER BY THAT WORD
    # AND NOTHING ELSE (fix round 2 — LOW-7). ** The example above would still pass with the clause
    # deleted, because every other fixture in it fails a different clause: a one-off on the whole
    # category is the shape of a GOAL and of an un-itemised BILL alike — the quarterly tax estimate,
    # the annual registration — and the walk cannot tell them apart, because it is the same walk.
    # The word the user chose is the only thing that can, so it is pinned by itself.
    it "tells a goal from a one-off bill by the type alone", :aggregate_failures do
      goal = create(:budget, :by_date, :choice, category: groceries, amount: 3_000)
      tax = create(:budget, :by_date, :bill, category: holder("Tax Estimate"), amount: 3_000)

      expect(goal.slice(:amount, :basis, :interval_months, :anchor_date))
        .to eq(tax.slice(:amount, :basis, :interval_months, :anchor_date))
      expect(described_class.saving_toward_a_date.to_a).to eq([goal])
    end

    # AND `usage` IS SAVING TOO, which is what keeps the clause from being read as "only `choice`":
    # a house deposit is a need the household is putting money aside for, and the only word that
    # takes a category off this band is the one that says somebody else sets the day.
    it "keeps a usage one-off, because only a bill is not savings" do
      deposit = create(:budget, :by_date, :usage, category: groceries, amount: 10_000)

      expect(described_class.saving_toward_a_date.to_a).to eq([deposit])
    end

    # THE FORM THE DASHBOARD COMPOSES IT IN, because a scope that cannot be a subquery is a scope
    # that reader cannot use.
    it "composes as a category subquery" do
      rules = planted

      expect(Category.where(id: described_class.saving_toward_a_date.select(:category_id)))
        .to contain_exactly(rules.fetch(:one_off).category)
    end
  end

  # ** ONE CATEGORY, ONE BUDGET LINE (two-ledger spec §3), NOW THAT THE LINE IS A CLAIM (ruling of
  # 2026-09-03). ** An item-less rule's spending lane is the whole category, so two of them on one
  # category subtract the same entries twice — and `Category#claim` sums them, so neither rule is
  # wrong on its own.
  describe "one item-less rule per category" do
    let(:groceries) { create(:category, :expense, :funded, name: "Groceries") }

    before { create(:budget, :per_period_rate, category: groceries, amount: 400) }

    it "refuses a second rule that covers the whole category", :aggregate_failures do
      second = build(:budget, :per_period_rate, category: groceries, amount: 75)

      expect(second).not_to be_valid
      expect(second.errors[:base]).to include(/already has a rule covering all of its spending/)
    end

    # ITEM-BACKED RULES ARE UNTOUCHED: their lanes are disjoint by construction, so a category may
    # carry one catch-all rule and as many dated bills as it has items.
    it "takes any number of rules that each name their own item", :aggregate_failures do
      expect(on_its_own_item("Phone", 75)).to be_valid
      expect(on_its_own_item("Water", 30)).to be_valid
    end

    def on_its_own_item(name, amount)
      build(
        :budget,
        :per_period_rate,
        category: groceries,
        amount: amount,
        item: create(:item, category: groceries, name: name)
      )
    end

    # AN EDIT DOES NOT COLLIDE WITH ITSELF — `where.not(id: id)`, the same guard
    # `#item_must_not_be_claimed` carries.
    it "lets the one item-less rule it already has be edited" do
      standing = groceries.budgets.sole

      expect(standing.update(amount: 500)).to be(true)
    end

    it "leaves another category's catch-all rule alone" do
      elsewhere = create(:category, :expense, :funded, name: "Transport")

      expect(build(:budget, :per_period_rate, category: elsewhere, amount: 75)).to be_valid
    end
  end

  # ONE OWNER, AND IT IS A CATEGORY (two-ledger spec §3, Task 8). `#exactly_one_owner` policed a
  # pair while a rule could be owned by a category OR a pool, and `#must_have_an_owner` accepted
  # either while both lanes stood; `budgets.pool_id` is gone, so there is one owner to have or lack.
  # Both directions, because "must belong to a category" is worth nothing if a rule with one is also
  # refused.
  describe "category ownership is required" do
    let(:user) { create(:user) }

    it "is valid attached to a category" do
      expect(build(:budget, :rate, category: create(:category, :expense, :funded, user: user))).to be_valid
    end

    # THE MESSAGE NAMES THE CATEGORY (two-ledger spec §3, Task 5), and the wording is about the
    # SCREEN rather than the schema: `budgets/_form` is the only form that can submit this state and
    # the control it offers is a category picker, so the sentence has to describe the form the user
    # is looking at.
    it "rejects a rule attached to nothing", :aggregate_failures do
      budget = build(:budget, category: nil)

      expect(budget).not_to be_valid
      expect(budget.errors[:base]).to include("must belong to a category")
    end
  end

  # THE CATEGORY-SIDE ANALOGUE of "cannot be an account" (two-ledger spec §2/§3, fix round 1). Income
  # lands in AVAILABLE and is allocated out of it, so an income category holds nothing ever — a
  # funding rule on one is a standing claim on money no `Category#holder?` can be true of. Both
  # directions, because a validation asserted only where it fires says nothing about what it lets
  # through, and the expense case here is the one the whole app writes.
  describe "category ownership" do
    let(:user) { create(:user) }

    it "is valid on an expense category" do
      expect(build(:budget, :rate, category: create(:category, :expense, :funded, user: user))).to be_valid
    end

    it "rejects a rule on an income category", :aggregate_failures do
      budget = build(:budget, :rate, category: create(:category, :income, user: user))

      expect(budget).not_to be_valid
      expect(budget.errors[:category]).to include("must be an expense category")
    end

    # THE HOLE THIS CLOSED, STATED AS THE RECORD RATHER THAN THE ROUTE. `BudgetProposal` stamps
    # `funded_since`, which `Category#only_expenses_hold_money` refuses on an income category — so
    # `POST /budgets` was already answered and `PATCH` was not, because `#update` writes straight
    # through. A rule that saved clean there counted into `Budget.steady_need` and could never be
    # filled by any distribution, because `Category.in_fill_order` is holders.
    it "refuses the re-parent that used to save clean", :aggregate_failures do
      rule = create(:budget, :rate, category: create(:category, :expense, :funded, user: user))
      income = create(:category, :income, user: user)

      expect(rule.update(category: income)).to be(false)
      expect(rule.reload.category).not_to eq(income)
    end
  end

  describe "the four valid shapes" do
    let(:user) { create(:user) }
    let(:owner) { create(:category, :expense, :funded, user: user) }

    it "accepts a per-period rate rule" do
      budget = build(
        :budget,
        category: owner,
        anchor_date: nil,
        interval_months: nil,
        basis: :per_period
      )

      expect(budget).to be_valid
    end

    it "accepts a monthly rate rule" do
      budget = build(
        :budget,
        category: owner,
        anchor_date: nil,
        interval_months: 1,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "accepts a recurring obligation" do
      budget = build(
        :budget,
        category: owner,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: 6,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "accepts a one-time obligation" do
      budget = build(
        :budget,
        category: owner,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: nil,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "rejects a per-period rule with an anchor date", :aggregate_failures do
      budget = build(
        :budget,
        category: owner,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: nil,
        basis: :per_period
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:basis]).to include("per-period rules cannot have a due date or interval")
    end

    it "rejects a monthly rule with neither an anchor nor an interval", :aggregate_failures do
      budget = build(
        :budget,
        category: owner,
        anchor_date: nil,
        interval_months: nil,
        basis: :monthly
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("is required for a monthly rule with no due date")
    end

    it "rejects a non-positive interval", :aggregate_failures do
      budget = build(:budget, category: owner, interval_months: 0, basis: :monthly)

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("must be greater than 0")
    end

    # The fifth shape. Not a row in the table: a multi-month interval with no
    # anchor is row 3 missing its due date, and the calculator would read the due
    # date as the end of this month and demand all N months of money at once.
    it "rejects a multi-month interval with no anchor date", :aggregate_failures do
      budget = build(
        :budget,
        category: owner,
        anchor_date: nil,
        interval_months: 6,
        basis: :monthly
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("must be 1 for a monthly rule with no due date")
    end

    # The other combination that was unasserted in both directions: the existing
    # per-period rejection only exercises the anchor_date half of that guard.
    it "rejects a per-period rule with an interval", :aggregate_failures do
      budget = build(
        :budget,
        category: owner,
        anchor_date: nil,
        interval_months: 6,
        basis: :per_period
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:basis]).to include("per-period rules cannot have a due date or interval")
    end
  end

  # THE FOUR SHAPES ABOVE, READ BACK OUT AS ONE SYMBOL. `HomeHelper#pool_rule_label` and
  # `BudgetPageHelper#budget_rule_basis` each held a copy of this cascade, in the same
  # hazard-ordered sequence; the classification lives here now and the two helpers keep only
  # their own words. Every arm is asserted, because a helper reduced to a lookup can no longer
  # catch a misclassification itself.
  describe "#cadence" do
    def pool_rule(*traits, **attrs) = build(:budget, *traits, **attrs)

    it "calls a per-period rate rule per-period" do
      expect(pool_rule(:per_period_rate).cadence).to eq(:per_period)
    end

    it "calls an anchorless monthly rate rule monthly" do
      expect(pool_rule(:rate).cadence).to eq(:monthly)
    end

    it "calls an anchored one-month rule monthly" do
      expect(pool_rule(interval_months: 1, anchor_date: Date.new(2026, 3, 1)).cadence).to eq(:monthly)
    end

    it "calls a multi-month rule every_n rather than naming the number" do
      expect(pool_rule(interval_months: 6, anchor_date: Date.new(2026, 3, 1)).cadence).to eq(:every_n)
    end

    it "calls an interval-less anchored rule a one-off" do
      expect(pool_rule(:one_time).cadence).to eq(:one_off)
    end

    # THE ONE ORDER HAZARD LEFT, in the direction that would misfire if the cascade were
    # rearranged: a per-period rule carries no interval either, so an interval-first cascade calls
    # every rate rule a one-off. The second hazard was a category cap, which carried no interval at
    # all and had to be answered before the same arm; the cap is deleted and the arm it needed with
    # it, so the example that pinned it is gone rather than rewritten against a shape that no
    # longer exists.
    it "never reads a per-period rule's blank interval as a one-off", :aggregate_failures do
      expect(pool_rule(:per_period_rate).interval_months).to be_nil
      expect(pool_rule(:per_period_rate).cadence).not_to eq(:one_off)
    end
  end

  # THE RENAME IS RUBY-SIDE ONLY. `per_paycheck` became `per_period` with no migration, so the
  # stored mapping `{ monthly: 0, per_period: 1 }` has to be exactly what it was — a rule written
  # under the old name still sits in the column as the integer 1, and every one of them would read
  # as `monthly` if the rename had re-numbered the enum. The two directions are asserted separately
  # because either alone can pass on a consistently-wrong mapping: the write asserts the integer
  # the new name produces, and the raw-SQL plant asserts what a row written before the rename now
  # reads as.
  describe "the stored basis mapping" do
    let(:rule) { create(:budget, :per_period_rate, amount: 300) }

    def raw_basis(record)
      Budget.connection.select_value(Budget.sanitize_sql_array(["SELECT basis FROM budgets WHERE id = ?", record.id]))
    end

    it "writes per_period as the integer 1" do
      expect(raw_basis(rule)).to eq(1)
    end

    it "writes monthly as the integer 0" do
      expect(raw_basis(create(:budget, :rate, amount: 300))).to eq(0)
    end

    # Planted by SQL rather than by the enum writer, because a row created before the rename is
    # exactly what no Ruby-side spelling can produce today.
    it "reads a row planted at 1 as per_period", :aggregate_failures do
      planted = create(:budget, :rate, amount: 300)
      described_class.connection.execute(described_class.sanitize_sql_array(["UPDATE budgets SET basis = 1 WHERE id = ?", planted.id]))

      planted.reload

      expect(planted).to be_basis_per_period
      expect(planted.basis).to eq("per_period")
    end
  end

  describe "#user" do
    let(:user) { create(:user) }

    it "comes from the category that owns it" do
      owner = create(:category, :expense, :funded, user: user)

      expect(build(:budget, :rate, category: owner).user).to eq(user)
    end

    # The state the form re-renders in after a failed submission.
    it "is nil for an owner-less budget rather than raising" do
      expect(build(:budget, category: nil).user).to be_nil
    end
  end

  # WHAT THIS SCOPE IS NOW, AND WHAT IT DELIBERATELY NO LONGER PINS. It used to be a union — a rule
  # owned by one of the user's categories OR by one of their pools — and three examples here held
  # that category arm in place, including one asserting `user.budgets` (the association through
  # categories) still reached a cap. Plan 3, task 3 deletes the cap, the association and the arm,
  # so those examples are deleted with the behaviour rather than left failing.
  #
  # Every example that remains is a pair: what the relation must REACH, and what it must not — a
  # scope that returns everything passes every "finds it" assertion ever written.
  describe ".for_user" do
    let(:user) { create(:user) }
    let(:owner) { create(:category, :expense, :funded, user: user) }

    let(:stranger) { create(:user) }
    let(:stranger_category) { create(:category, :expense, :funded, user: stranger) }

    let!(:rule) { create(:budget, :rate, category: owner) }
    let!(:stranger_rule) { create(:budget, :rate, category: stranger_category) }

    it "returns the user's rules and nobody else's", :aggregate_failures do
      expect(described_class.for_user(user)).to contain_exactly(rule)
      expect(described_class.for_user(user)).not_to include(stranger_rule)
    end

    # What BudgetsController#set_budget does with it. Findability is the point of the
    # scope; raising on a stranger's id is the point of it still being a scope.
    it "finds a rule by id" do
      expect(described_class.for_user(user).find(rule.id)).to eq(rule)
    end

    it "raises RecordNotFound for another user's rule" do
      expect { described_class.for_user(user).find(stranger_rule.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    # The Budget page groups these, so the scope has to stay composable.
    it "chains with further conditions" do
      expect(described_class.for_user(user).where(category_id: owner.id)).to contain_exactly(rule)
    end
  end

  describe ":budget factory" do
    # Guards the interface later tasks build on: every shape trait must produce a
    # valid record under `build`, where associations are not yet persisted.
    it "builds a valid rate rule by default" do
      expect(build(:budget)).to be_valid
    end

    it "builds a valid record for every shape trait", :aggregate_failures do
      [:rate, :per_period_rate, :recurring, :one_time, :by_date].each do |trait|
        expect(build(:budget, trait)).to be_valid
      end
    end

    # THE TYPE TRAITS, and the assertion is the COLUMN rather than mere validity: a trait that
    # silently wrote nothing would pass a `be_valid` check, because `usage` is the default.
    it "builds a valid record typed by each type trait", :aggregate_failures do
      [:bill, :usage, :choice].each do |trait|
        expect(build(:budget, trait)).to be_valid
        expect(build(:budget, trait).rule_type).to eq(trait.to_s)
      end
    end
  end

  # THE POOL HALF OF THIS BLOCK IS DELETED (two-ledger spec §5, Task 8) —
  # `#item_must_belong_to_pool` and its six examples went with `budgets.pool_id`. What is left is
  # the twin one layer in, which is the only rule there is now.
  describe "item attribution" do
    let(:user) { create(:user) }
    let(:category) { create(:category, :expense, :funded, user: user) }
    let(:item) { create(:item, category: category) }

    # A dated bill anchors on an item, and the rule's owner is the category — so the item has to be
    # an item OF that category rather than of anything in an envelope's orbit. Both directions.
    context "when the rule is owned by a category" do
      let(:holder) { create(:category, :expense, :funded, user: user, name: "Insurance") }

      it "accepts an item of its own category" do
        budget = build(:budget, :category_rule, :recurring, category: holder, item: create(:item, category: holder))

        expect(budget).to be_valid
      end

      it "rejects an item belonging to another category", :aggregate_failures do
        budget = build(:budget, :category_rule, :recurring, category: holder, item: item)

        expect(budget).not_to be_valid
        expect(budget.errors[:item]).to include("must belong to this category")
      end

      # `#must_have_a_category` is the one line that makes "a rule has an owner" true while the
      # association stays `optional` — and the message names the CATEGORY, because that is the
      # owner the one form able to submit this state asks for.
      it "still refuses a rule owned by neither", :aggregate_failures do
        budget = build(:budget, :rate, category: nil)

        expect(budget).not_to be_valid
        expect(budget.errors[:base]).to include("must belong to a category")
      end

      # UNGATED, both of them: neither rule reads an owner at all, and a rule that skipped them
      # would be a second definition of what a rule's shape is.
      it "holds a category rule to the same shape rules and the same one-item-one-rule rule",
         :aggregate_failures do
           create(:budget, :category_rule, :recurring, category: holder, item: create(:item, category: holder))
           claimed = build(:budget, :category_rule, :recurring, category: holder, item: described_class.last.item)
           shapeless = build(:budget, :category_rule, category: holder, interval_months: 6, anchor_date: nil)

           expect(claimed.tap(&:valid?).errors[:item]).to include("is already used by another rule")
           expect(shapeless.tap(&:valid?).errors[:interval_months]).to include("must be 1 for a monthly rule with no due date")
         end
    end
  end
end
