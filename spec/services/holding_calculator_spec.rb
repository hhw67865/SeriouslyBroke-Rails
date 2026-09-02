# frozen_string_literal: true

require "rails_helper"

# THE PORT OF `spec/services/pool_calculator_spec.rb`, FIGURE FOR FIGURE (two-ledger Task 3). Every
# example that pinned a number keeps the number: a category holds what allocations put in it less
# what it spends, which is arithmetically the envelope's `movements_in − movements_out − expenses`
# with the nouns changed, so nothing about the maths moved and nothing about the maths may.
#
# WHAT COULD NOT COME ACROSS, and each is named where it stood:
#   * the income examples — income lands in AVAILABLE and never in a category (spec §2), so
#     `AccountLedger#income_within` owns the question and `HoldingCalculator` has no income term to
#     assert. The two examples that funded a pool with an income entry are rewritten to fund with
#     an allocation, which is how a category is funded.
#   * the per-entry pool override — `entries.pool_id` overrides a category's POOL, and there is no
#     such override on the purpose side: an entry drains the category of its item, full stop. The
#     both-directions shape it pinned survives as "counts its own items' entries and no others".
#   * the pool-TYPE discrimination — a category has no type. Its replacement is better isolated
#     rather than weaker: the pair at the bottom of "dateless savings goals" varies the TARGET
#     alone, on two categories identical in every other respect.
#   * the SECOND HALF of the pre-start balance example — the pool source also pinned the displaced
#     $40 landing in the account (`checking … -140.00`), and there is no account arm here: on the
#     purpose side that spending drains AVAILABLE, which is `CategoryLedger#available`'s figure and
#     not this class's. It is covered, at the same shape, by `spec/services/category_ledger_spec.rb`
#     "is income, less unfunded spending, less what is allocated out, plus what comes back", whose
#     `spend(food, 10, on: …)` line is spending dated before Food was funded. The half that IS this
#     class's — the category not counting it — stays here.
RSpec.describe HoldingCalculator, type: :model do
  let(:user) { create(:user) }

  # EVERY RULE IN THIS FILE BELONGS TO A CATEGORY, which is the only owner a rule has — said once
  # here rather than on every line.
  def rule(category, trait = nil, **attrs)
    create(:budget, *Array(trait), category: category, **attrs)
  end

  # A GOAL'S BALANCE, FUNDED THE WAY A GOAL IS FUNDED (spec §3): contributing is available →
  # category, withdrawing is spending out of the category's own items. Scoped to this group so it
  # does not leak into the envelope examples below.
  describe "savings-category balances" do
    let(:base_date) { Date.current.beginning_of_month }
    let!(:emergency) do
      create(
        :category,
        :expense,
        user: user,
        name: "Emergency Fund",
        target_amount: 10_000,
        funded_since: base_date - 6.months
      )
    end
    let!(:withdrawal_item) { create(:item, category: emergency, name: "Withdrawal") }

    def contribute(amount, on)
      create(:allocation, to_category: emergency, amount: amount, date: on)
    end

    before do
      # Contributions: $200 month-3, $300 month-2, $500 month-1, $400 this month
      contribute(200.00, base_date - 3.months + 1.day)
      contribute(300.00, base_date - 2.months + 1.day)
      contribute(500.00, base_date - 1.month + 1.day)
      contribute(400.00, base_date + 1.day)

      # Withdrawals: $100 month-2, $150 this month
      create(:entry, item: withdrawal_item, amount: 100.00, date: base_date - 2.months + 5.days)
      create(:entry, item: withdrawal_item, amount: 150.00, date: base_date + 5.days)
    end

    describe "date-scoped balance", :aggregate_failures do
      it "returns correct balance as_of 2 months ago" do
        calc = emergency.holding_calculator(as_of: (base_date - 2.months).end_of_month)

        expect(calc.contributions).to eq(500.00) # 200 + 300
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(400.00) # 500 - 100
        expect(calc.progress_percentage).to eq(4) # 400/10000 * 100
      end

      it "returns correct balance as_of 1 month ago" do
        calc = emergency.holding_calculator(as_of: (base_date - 1.month).end_of_month)

        expect(calc.contributions).to eq(1000.00) # 200 + 300 + 500
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(900.00) # 1000 - 100
        expect(calc.progress_percentage).to eq(9) # 900/10000 * 100
      end

      it "returns correct balance as_of current month end" do
        calc = emergency.holding_calculator(as_of: base_date.end_of_month)

        expect(calc.contributions).to eq(1400.00) # 200 + 300 + 500 + 400
        expect(calc.withdrawals).to eq(250.00) # 100 + 150
        expect(calc.current_balance).to eq(1150.00) # 1400 - 250
        expect(calc.progress_percentage).to eq(12) # 1150/10000 * 100 = 11.5, rounded to 12
      end

      it "returns all-time balance with no as_of date" do
        calc = emergency.holding_calculator

        expect(calc.current_balance).to eq(1150.00)
        expect(calc.remaining_amount).to eq(8850.00) # 10000 - 1150
      end
    end
  end

  # Regression, inherited whole: an envelope category legitimately has no target (only a goal
  # names one), which made #remaining_amount raise NoMethodError and took the page down with it.
  describe "categories with no target_amount", :aggregate_failures do
    it "returns zero instead of raising" do
      envelope = create(:category, :expense, :funded, user: user)

      expect(envelope.target_amount).to be_nil
      expect(envelope.holding_calculator.remaining_amount).to eq(0)
      # `nil.to_d` is 0, which is what makes the nil target safe without a guard.
      expect(envelope.holding_calculator.remaining_amount).to be_a(BigDecimal)
      expect(envelope.holding_calculator.progress_percentage).to eq(0)
    end
  end

  # THE FLOOR, IN BOTH DIRECTIONS. #progress_percentage capped at 100 and not at zero, so an
  # overdrawn category measured against a target answered a NEGATIVE percentage and every render
  # site drew it — a savings bar of negative width.
  #
  # BOTH DIRECTIONS, because a floor that also flattened real progress would be a worse bug than
  # the one it fixed: the overdrawn category reads 0, and a partly funded one reads its true
  # figure. The cap is asserted with it, since one clamp does both jobs.
  describe "#progress_percentage clamps at both ends", :aggregate_failures do
    let(:goal) { create(:category, :expense, :funded, user: user, name: "Clamped", target_amount: 1_000) }
    let(:spending) { create(:item, category: goal) }

    def contribute(amount) = create(:allocation, to_category: goal, amount: amount)

    it "floors at zero on an overdrawn category and reports the true figure on a partial one" do
      create(:entry, item: spending, amount: 300)

      expect(goal.holding_calculator.current_balance).to eq(-300) # the balance itself still says so
      expect(goal.holding_calculator.progress_percentage).to eq(0)

      contribute(550)

      expect(goal.holding_calculator.current_balance).to eq(250)
      expect(goal.holding_calculator.progress_percentage).to eq(25)
    end

    it "still caps at 100 when the goal is overfunded" do
      contribute(2_500)

      expect(goal.holding_calculator.progress_percentage).to eq(100)
    end
  end

  describe "envelope behaviour" do
    let(:envelope_user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
    let(:car) { create(:category, :expense, :funded, user: envelope_user, name: "Car") }

    # A method rather than a `let`: Date is immutable, so there is nothing to memoize.
    def today = Date.new(2026, 2, 6)

    describe "#balance" do
      it "counts allocations in, allocations out, and expense entries" do
        create(:allocation, to_category: car, amount: 700)
        create(:allocation, from_category: car, amount: 50)
        create(:entry, item: create(:item, category: car), amount: 70, date: today)

        expect(car.holding_calculator(today: today).balance).to eq(580.00)
      end

      # THE FUNDING DATE GATES ENTRIES AND NOT ALLOCATIONS, and the two halves are one semantic
      # rather than a rule with an exception. An entry is dated SPENDING, and the re-anchored
      # start-date rule (spec §4) says a category only counts the spending of its own life —
      # earlier spending drained AVAILABLE and reads there. An allocation is money put into the
      # category by name; there is no category to date it against and money somebody deliberately
      # allocated before the funding date is still in there.
      it "gates pre-funding entries out and still counts pre-funding allocations", :aggregate_failures do
        car.update!(funded_since: Date.new(2026, 6, 1))
        create(:allocation, to_category: car, amount: 100, date: Date.new(2026, 1, 20))
        create(:entry, item: create(:item, category: car), amount: 40, date: Date.new(2026, 1, 15))

        expect(car.funded_since).to be > Date.new(2026, 1, 20)
        expect(car.holding_calculator(today: today).balance).to eq(100.00)
      end

      it "goes negative when a category is overspent" do
        create(:allocation, to_category: car, amount: 100)
        create(:entry, item: create(:item, category: car), amount: 150, date: today)

        expect(car.holding_calculator(today: today).balance).to eq(-50.00)
      end

      # `as_of` is a ledger question — which rows had happened by then — so it has to reach the
      # allocations as well as the entries.
      it "applies as_of to allocations", :aggregate_failures do
        create(:allocation, to_category: car, amount: 500, date: Date.new(2026, 1, 10))
        create(:allocation, from_category: car, amount: 100, date: Date.new(2026, 2, 10))

        expect(car.holding_calculator(as_of: Date.new(2026, 1, 31), today: today).balance).to eq(500.00)
        expect(car.holding_calculator(today: today).balance).to eq(400.00)
      end

      # The port of the per-entry pool override, which has no purpose-side twin: an entry drains
      # the category of its own item and nothing else. Asserted in both directions on purpose —
      # the other category must GAIN it and this one must LOSE it, and a reader that only summed
      # "entries whose user matches" would pass the first half.
      it "counts its own items' entries and no others", :aggregate_failures do
        maintenance = create(:category, :expense, :funded, user: envelope_user, name: "Maintenance")
        create(:allocation, to_category: car, amount: 300)
        create(:allocation, to_category: maintenance, amount: 300)
        create(:entry, item: create(:item, category: maintenance), amount: 100, date: today)

        expect(car.holding_calculator(today: today).balance).to eq(300.00)
        expect(maintenance.holding_calculator(today: today).balance).to eq(200.00)
      end
    end

    describe "#allocated_balances" do
      # Spec §4.4 — earliest due date fills first.
      let!(:gas) { rule(car, :rate, amount: 80) }
      let!(:insurance) do
        rule(car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end
      let!(:registration) do
        rule(car, amount: 180, interval_months: 12, anchor_date: Date.new(2026, 8, 15))
      end

      it "fills by due date and leaves nothing free", :aggregate_failures do
        create(:allocation, to_category: car, amount: 580)
        calc = car.holding_calculator(today: today)

        expect(calc.allocated_balances[gas]).to eq(80.00)
        expect(calc.allocated_balances[insurance]).to eq(500.00)
        expect(calc.allocated_balances[registration]).to eq(0)
        expect(calc.free_amount).to eq(0)
      end

      it "reports the surplus beyond every rule as free" do
        create(:allocation, to_category: car, amount: 1_000)

        expect(car.holding_calculator(today: today).free_amount).to eq(140.00)
      end

      it "gives every rule zero when the category is negative", :aggregate_failures do
        create(:entry, item: create(:item, category: car), amount: 50, date: today)
        calc = car.holding_calculator(today: today)

        expect(calc.allocated_balances.values).to all(eq(0))
        expect(calc.free_amount).to eq(0)
      end

      it "totals the category's requirement across its rules" do
        create(:allocation, to_category: car, amount: 580)

        # gas $0 + insurance $50.00 + registration $12.86
        expect(car.holding_calculator(today: today).required).to eq(62.86)
      end

      it "raises the requirement after an unexpected expense" do
        create(:allocation, to_category: car, amount: 580)
        create(:entry, item: create(:item, category: car, name: "New tires"), amount: 420, date: today)

        # gas $0 + insurance $260.00 + registration $12.86
        expect(car.holding_calculator(today: today).required).to eq(272.86)
      end
    end

    # `[BigDecimal, 0].max` returns the bare Integer literal on the negative branch, so the return
    # type of both methods depended on whether the category happened to be in the black. The sweep
    # divides by #free_amount; money math must not change type under it.
    describe "money types on the negative branch", :aggregate_failures do
      it "returns a BigDecimal zero from #free_amount when the category is overdrawn" do
        rule(car, :rate, amount: 80)
        create(:entry, item: create(:item, category: car), amount: 50, date: today)
        calc = car.holding_calculator(today: today)

        expect(calc.free_amount).to eq(0)
        expect(calc.free_amount).to be_a(BigDecimal)
      end

      it "returns a BigDecimal zero from #remaining_amount when the goal is exceeded" do
        goal = create(:category, :expense, :funded, user: envelope_user, target_amount: 100)
        create(:allocation, to_category: goal, amount: 250)
        calc = goal.holding_calculator(today: today)

        expect(calc.remaining_amount).to eq(0)
        expect(calc.remaining_amount).to be_a(BigDecimal)
      end

      # The positive branch, pinned alongside the negative one so the pair proves the type no
      # longer depends on which way the subtraction went.
      it "returns a BigDecimal from #remaining_amount when the goal is unmet" do
        goal = create(:category, :expense, :funded, user: envelope_user, target_amount: 100)
        create(:allocation, to_category: goal, amount: 30.10)
        calc = goal.holding_calculator(today: today)

        expect(calc.remaining_amount).to eq(69.90)
        expect(calc.remaining_amount).to be_a(BigDecimal)
      end
    end

    # The shape the `[x, 0.to_d].max` idiom never covered: `max` only coerces when the clamp
    # FIRES, and `[0, BigDecimal("0")].max` returns the Integer. An empty `sum(:amount)` over a
    # `money` column returns Integer 0 too, so a category holding nothing at all — a fresh
    # envelope, the first thing a sweep meets — answered every money question in the wrong type.
    describe "money types on a category with nothing in it at all", :aggregate_failures do
      it "answers in BigDecimal from an empty ledger" do
        rule(car, :rate, amount: 80)
        calc = car.holding_calculator(today: today)

        expect(calc.balance).to eq(0)
        expect(calc.balance).to be_a(BigDecimal)
        expect(calc.reserve).to eq(0)
        expect(calc.reserve).to be_a(BigDecimal)
        expect(calc.free_amount).to eq(0)
        expect(calc.free_amount).to be_a(BigDecimal)
      end

      # And with no rules either, so #reserve sums an empty hash rather than a hash of clamped
      # zeroes. Two different Integer sources, one per example.
      it "answers in BigDecimal with no rules to reserve against" do
        calc = car.holding_calculator(today: today)

        expect(calc.allocated_balances).to be_empty
        expect(calc.reserve).to be_a(BigDecimal)
        expect(calc.free_amount).to be_a(BigDecimal)
      end
    end

    # `remaining.clamp(0, budget.amount)` raises ArgumentError whenever amount is negative, taking
    # down allocated_balances, reserve, free_amount and required — the whole page. Budget
    # validates the sign, so this writes past the validation to prove the rendering path survives
    # a degenerate row however it got there.
    describe "#allocated_balances with a degenerate rule amount" do
      it "gives the bad rule nothing and keeps the waterfall intact", :aggregate_failures do
        gas = rule(car, :rate, amount: 80)
        broken = rule(car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
        broken.update_column(:amount, -100) # rubocop:disable Rails/SkipsModelValidations -- the point
        create(:allocation, to_category: car, amount: 500)
        calc = car.holding_calculator(today: today)

        expect(broken.reload.amount).to be_negative
        expect(calc.allocated_balances[broken]).to eq(0)
        expect(calc.allocated_balances[gas]).to eq(80.00)
        expect(calc.free_amount).to eq(420.00)
      end
    end

    # `sort_by` is not stable in Ruby, so a bare due-date sort let two rules sharing a due date
    # swap fill order between calls — the same category reporting different `required` figures on
    # consecutive page loads with no data change. Money must not be a coin flip.
    describe "#allocated_balances when two rules share a due date" do
      let!(:big) do
        rule(car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end
      let!(:small) do
        rule(car, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end

      it "fills the larger obligation first", :aggregate_failures do
        create(:allocation, to_category: car, amount: 500)
        calc = car.holding_calculator(today: today)

        expect(big.calculator(today: today).due_date).to eq(small.calculator(today: today).due_date)
        expect(calc.allocated_balances[big]).to eq(500.00)
        expect(calc.allocated_balances[small]).to eq(0)
      end
    end

    # A category carrying no rules at all — the shape the reallocation screen hands money to and
    # the one a sweep reads. Funded by an allocation rather than by the income entry the pool-era
    # example used: income lands in available and never in a category.
    describe "#free_amount for a category with no rules" do
      it "reports the entire balance as free", :aggregate_failures do
        spare = create(:category, :expense, :funded, user: envelope_user, name: "Spare")
        create(:allocation, to_category: spare, amount: 1_200)
        calc = spare.holding_calculator(today: today)

        expect(calc.allocated_balances).to be_empty
        expect(calc.reserve).to eq(0)
        expect(calc.free_amount).to eq(1_200.00)
        expect(calc.required).to eq(0)
        # An unseeded `sum` over an empty rule set returns the Integer literal 0, making
        # #required's type depend on whether the category happens to hold any rules.
        expect(calc.required).to be_a(BigDecimal)
      end
    end
  end

  # DATELESS GOALS, AND THE ONE THING THAT MOVED IN THIS PORT (reported with the task).
  #
  # `PoolCalculator#dateless_goal?` asked `pool.pool_type_savings?`, and a category has no type to
  # ask. `Category#savings?` is the model's answer to "is this a goal" and it is DELIBERATELY
  # NARROWER than this question: it also requires the category to carry NO RULE, which is the
  # display sentence Task 7's screens need. Asked here it would make this whole branch inert —
  # a goal with no rules has no rate to contribute, so `goal_required` would answer 0 for every
  # category that could reach it, which is what #required already answers without the branch.
  #
  # So the calculator asks its own narrower question, exactly as `PoolStatus#saving?` and
  # `PoolCalculator#dateless_goal?` were already two deliberately different conditions: a HOLDER
  # WITH A POSITIVE TARGET AND NO DATED RULE is saving toward a figure. The demo's Retirement
  # Supplement — a goal with a $150 per-period rule and a $100,000 target — is exactly the shape
  # `savings?` would have re-classified as an envelope, and an envelope is swept: its whole
  # balance would go back to available on the first distribution after its rate period closed.
  describe "dateless savings goals" do
    let(:goal_user) { create(:user, :biweekly) }
    let(:vacation) do
      create(:category, :expense, :funded, user: goal_user, name: "Vacation", target_amount: 2_400)
    end
    let(:today) { Date.new(2026, 2, 6) }

    before { rule(vacation, :per_period_rate, amount: 150) }

    def fund(category, amount) = create(:allocation, to_category: category, amount: amount)

    # The whole progression, in order, because "a dateless goal is just a rate rule plus a target"
    # is the reading this group exists to disprove. An ordinary rate rule is satisfied at its OWN
    # amount — correct for a budget envelope, which is swept and topped back up every period, and
    # wrong for a goal, which never sweeps: under that reading the second example below returns 0
    # and a $2,400 goal reports itself funded forever at $150.
    it "asks for its rate while below the target" do
      expect(vacation.holding_calculator(today: today).required).to eq(150)
    end

    # $600 of $2,400 saved. The rule's amount is a contribution rate, not a per-period ceiling, so
    # a part-funded goal keeps asking for the whole rate.
    it "still asks for the full rate when partly funded" do
      fund(vacation, 600)

      expect(vacation.holding_calculator(today: today).required).to eq(150)
    end

    # $100 short with a $150 rate: asking for the rate would overshoot the target the user set, so
    # the final contribution is the remainder.
    it "asks only for the remainder when less than a rate is left" do
      fund(vacation, 2_300)

      expect(vacation.holding_calculator(today: today).required).to eq(100)
    end

    it "stops asking once the balance reaches the target" do
      fund(vacation, 2_400)

      expect(vacation.holding_calculator(today: today).required).to eq(0)
    end

    it "stops asking when overfunded" do
      fund(vacation, 2_500)

      expect(vacation.holding_calculator(today: today).required).to eq(0)
    end

    # `0.to_d`, not a bare `0`: #required feeds a summing caller, so a reached goal must not make
    # the return type depend on how well funded the category is.
    it "returns a BigDecimal zero from the reached branch" do
      fund(vacation, 2_400)

      expect(vacation.holding_calculator(today: today).required).to be_a(BigDecimal)
    end

    # Budget blesses two dateless shapes and their amounts are in different units: a per_period
    # rule's amount IS the per-period rate, while a monthly rule's is a per-month figure. Summing
    # the two bases raw would ask $600 a fortnight. `Budget#steady_ask` says 600 * 12 / 26 =
    # $276.92 a period, every month, because 26 periods a year is what biweekly means.
    it "converts a monthly rate to a per-period figure" do
      monthly_goal = create(:category, :expense, :funded, user: goal_user, name: "Monthly", target_amount: 2_400)
      rule(monthly_goal, :rate, amount: 600)

      expect(monthly_goal.holding_calculator(today: today).required).to eq(BigDecimal("276.92"))
    end

    # THE GUARANTEE ACROSS MONTHS AS WELL AS WITHIN ONE. Asked on Feb 20, the month's last
    # boundary, the goal still contributes its rate rather than the $600 that dividing by the
    # periods REMAINING would give; and Feb 6, Feb 20 and Mar 6 all read the same, which a
    # month-counting normaliser cannot do. Three literals rather than three comparisons to each
    # other, so a method returning a constant wrong answer cannot pass by being consistent.
    it "asks the same rate whenever it is asked, in any month", :aggregate_failures do
      monthly_goal = create(:category, :expense, :funded, user: goal_user, name: "Monthly", target_amount: 2_400)
      rule(monthly_goal, :rate, amount: 600)

      expect(monthly_goal.holding_calculator(today: Date.new(2026, 2, 20)).required).to eq(BigDecimal("276.92"))
      expect(monthly_goal.holding_calculator(today: Date.new(2026, 3, 6)).required).to eq(BigDecimal("276.92"))
      expect(monthly_goal.holding_calculator(today: Date.new(2026, 8, 15)).required).to eq(BigDecimal("276.92"))
    end

    # Both bases on one goal, each normalised before adding: $150 a period plus $600 a month.
    it "adds rules of different bases in the same unit" do
      rule(vacation, :rate, amount: 600)

      expect(vacation.holding_calculator(today: today).required).to eq(BigDecimal("426.92"))
    end

    # A user with no cadence has no boundaries at all, so the monthly amount cannot be divided
    # into periods. Falling back to the full amount is a wrong-but-safe answer; dividing by zero
    # takes down every page that renders a requirement.
    it "falls back to the full monthly amount for a user with no cadence configured" do
      cadence_less = create(:user)
      goal = create(:category, :expense, :funded, user: cadence_less, target_amount: 2_400)
      rule(goal, :rate, amount: 600)

      expect(goal.holding_calculator(today: today).required).to eq(600)
    end

    # A goal with a deadline is not a dateless goal. The anchored maths spreads the $600 across
    # the 13 pay periods between today and Aug 1 — $46.15 a period — and must keep winning; the
    # dateless path would ask for the whole $600 now.
    it "leaves an anchored goal to the scheduled maths" do
      deadline_goal = create(:category, :expense, :funded, user: goal_user, name: "Roof", target_amount: 2_400)
      rule(deadline_goal, :one_time, amount: 600)

      expect(deadline_goal.holding_calculator(today: today).required).to eq(46.15)
    end

    it "does not apply the cutoff to a category with no target" do
      envelope = create(:category, :expense, :funded, user: goal_user, name: "Groceries")
      rule(envelope, :per_period_rate, amount: 150)

      expect(envelope.holding_calculator(today: today).required).to eq(150)
    end

    # THE PAIR, AT ONE IDENTICAL BALANCE so the only difference between the two answers is the
    # TARGET. This is the pool-type discrimination re-pinned on the column that replaced the type,
    # and it is a stricter test than the one it replaces: two categories built by the same method,
    # differing in one attribute.
    it "stops asking, in BigDecimal, once a target below the rate is reached", :aggregate_failures do
      calc = category_at_a_target_below_its_rate(2_400 - 2_300).holding_calculator(today: today)

      expect(calc.required).to eq(0)
      expect(calc.required).to be_a(BigDecimal)
    end

    # No target is no goal: at the identical balance the envelope keeps asking for the $50 still
    # missing from this period's $150.
    it "keeps a category with no target asking for the rest of its rate at the same balance" do
      calc = category_at_a_target_below_its_rate(nil).holding_calculator(today: today)

      expect(calc.required).to eq(50)
    end

    # $100 target (or none), $150 a period, $100 in the category.
    def category_at_a_target_below_its_rate(target)
      create(:category, :expense, :funded, user: goal_user, target_amount: target).tap do |category|
        rule(category, :per_period_rate, amount: 150)
        fund(category, 100)
      end
    end
  end

  # A rate envelope whose period has ended still HOLDS its leftover until a distribution moves it,
  # so the question these answer is "is that money spoken for by a period that is over" — never
  # "should the screen pretend the money is gone".
  #
  # `today` is Thu 20 Aug 2026, the last day of a biweekly period anchored Fri 6 Feb 2026:
  # boundaries fall on Aug 7 and Aug 21, so money dated Aug 15 is inside the live period and money
  # dated Jul 12 is two periods back. Fixed rather than relative because every expectation here
  # turns on which side of a boundary a date sits.
  describe "closed periods and sweeping" do
    let(:sweep_user) { create(:user, :biweekly) }
    let(:today) { Date.new(2026, 8, 20) }
    let(:last_period) { Date.new(2026, 7, 12) }
    let(:this_period) { Date.new(2026, 8, 15) }

    def envelope(name:, **attrs)
      create(:category, :expense, :funded, user: sweep_user, name: name, **attrs)
    end

    def fund(category, amount, on:)
      create(:allocation, to_category: category, amount: amount, date: on)
    end

    def spend(category, amount, on:)
      create(:entry, item: create(:item, category: category), amount: amount, date: on)
    end

    def calc(category) = category.holding_calculator(today: today)

    # The positive direction. $60 left in Groceries from a period that ended a month ago: the
    # money is still in the category, and the next distribution takes it back.
    it "sweeps a rate envelope's leftover once its period has ended", :aggregate_failures do
      groceries = envelope(name: "Groceries")
      rule(groceries, :per_period_rate, amount: 400)
      fund(groceries, 60, on: last_period)

      expect(calc(groceries).period_closed?).to be(true)
      expect(calc(groceries).sweepable_amount).to eq(60)
      expect(calc(groceries).sweepable_amount).to be_a(BigDecimal)
    end

    # The negative direction at the same shape and the same balance: the only difference is which
    # side of Aug 7 the money arrived on. Without this the example above passes against a
    # #period_closed? hard-coded to true.
    it "leaves a rate envelope funded inside the live period alone", :aggregate_failures do
      groceries = envelope(name: "Groceries")
      rule(groceries, :per_period_rate, amount: 400)
      fund(groceries, 60, on: this_period)

      expect(calc(groceries).period_closed?).to be(false)
      expect(calc(groceries).sweepable_amount).to eq(0)
      expect(calc(groceries).sweepable_amount).to be_a(BigDecimal)
    end

    # THE trap, and the reason the sweep is gated on the TARGET rather than on the rule shape. A
    # dateless goal IS a rate rule on a category, so eligibility written as "has a rate rule whose
    # period ended" drains every goal the user has. #free_amount is asserted alongside because it
    # is the number a naive sweep would reach for: #required reads the $150 as a contribution rate
    # while #allocated_balances still clamps the reserve to the rule's own $150, so this goal
    # reports $450 free. Savings accumulate by definition, so they never sweep.
    it "never sweeps a savings goal, whatever its rate rule's period says", :aggregate_failures do
      vacation = envelope(name: "Vacation", target_amount: 2_400)
      rule(vacation, :per_period_rate, amount: 150)
      fund(vacation, 600, on: last_period)

      expect(calc(vacation).free_amount).to eq(450)
      expect(calc(vacation).period_closed?).to be(false)
      expect(calc(vacation).sweepable_amount).to eq(0)
      expect(calc(vacation).sweepable_amount).to be_a(BigDecimal)
    end

    # THE SAME REFUSAL AT THE ONE SHAPE THAT WALKED PAST IT (fix round 1, MED-1). A goal carrying
    # BOTH a rate rule and a dated one is not a `dateless_goal?` — the anchored maths owns its
    # funding — and gating the sweep on that predicate let it fall through to the envelope path:
    # measured at `period_closed?` true and `sweepable_amount` $300 before the fix, which is the
    # user's savings going back to available on the next distribution. The pool era refused every
    # savings sweep by TYPE and no rule mix could argue with a type; the target has to refuse at
    # the same width.
    #
    # $600 allocated last period, the $300 bill holding $300 of it: the figure at risk is exactly
    # the $300 the bill is NOT holding, so `eq(0)` here is a real refusal rather than an empty
    # envelope answering zero by having nothing.
    it "never sweeps a savings goal, whatever mix of rules it carries", :aggregate_failures do
      vacation = envelope(name: "Vacation", target_amount: 2_400)
      rule(vacation, :per_period_rate, amount: 150)
      rule(vacation, amount: 300, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(vacation, 600, on: last_period)

      expect(calc(vacation).balance).to eq(600)
      expect(calc(vacation).dateless_goal?).to be(false)
      expect(calc(vacation).period_closed?).to be(false)
      expect(calc(vacation).sweepable_amount).to eq(0)
    end

    # The other direction, and the only variable is the TARGET: the identical rule mix on a
    # category saving toward nothing is an envelope, its rate period is over, and the $300 its
    # live bill is not holding goes back. Without this the example above passes against a sweep
    # that has simply stopped working.
    it "sweeps the same rule mix on a category with no target", :aggregate_failures do
      groceries = envelope(name: "Groceries")
      rule(groceries, :per_period_rate, amount: 150)
      rule(groceries, amount: 300, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(groceries, 600, on: last_period)

      expect(calc(groceries).balance).to eq(600)
      expect(calc(groceries).period_closed?).to be(true)
      expect(calc(groceries).sweepable_amount).to eq(300)
    end

    # An anchored rule is money already spoken for by a bill nobody has paid yet, so the sweep
    # must not take it — but a RECURRING dated rule is never `fulfilled?` (there is always a next
    # occurrence), so gating the whole envelope on it would strand the rate rule's genuine
    # leftover in every period, permanently. The sweep is partial instead: the bill keeps what it
    # holds, the rest goes back.
    #
    # All three numbers are pinned and all three differ, so the example cannot pass on a fixture
    # where balance, reserve and sweepable happen to coincide: $900 in, the bill is holding $500
    # of it, $400 comes back.
    it "sweeps a mixed envelope down to what its live bill is holding", :aggregate_failures do
      car = envelope(name: "Car")
      rate = rule(car, :per_period_rate, amount: 100)
      rent = rule(car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(car, 900, on: last_period)

      expect(calc(car).balance).to eq(900)
      expect(calc(car).allocated_balances[rent]).to eq(500)
      expect(calc(car).allocated_balances[rate]).to eq(100)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(400)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # Under-funded: $300 against a $500 bill. The reserve is by ALLOCATION, not by the rule's
    # amount, and #allocated_balances fills earliest-due first — the rate rule is due at this
    # period's end (Aug 20) and the bill not until Sep 1, so the rate rule takes its $100 and the
    # bill reserves only the $200 left. $100 therefore still comes back, and it should: that is
    # last period's unspent grocery money, not rent.
    it "reserves what an under-funded bill actually holds, not what it wants", :aggregate_failures do
      car = envelope(name: "Car")
      rent = rule(car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      rule(car, :per_period_rate, amount: 100)
      fund(car, 300, on: last_period)

      expect(calc(car).balance).to eq(300)
      expect(calc(car).allocated_balances[rent]).to eq(200)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(100)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # The other direction of the same idea, and the one that reaches zero: when the bill is the
    # earlier claim it fills FIRST and swallows the whole under-funded balance, leaving the rate
    # rule nothing to give back. A monthly rate rule ends Aug 31 while this bill, anchored Jul 25,
    # comes round again on Aug 25 — so the bill sorts ahead of it.
    it "sweeps nothing when the live bill's allocation takes the whole balance", :aggregate_failures do
      car = envelope(name: "Car")
      rent = rule(car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 7, 25))
      rule(car, :rate, amount: 100)
      fund(car, 400, on: last_period)

      expect(calc(car).balance).to eq(400)
      expect(calc(car).allocated_balances[rent]).to eq(400)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(0)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
      # The one shape where #free_amount and #sweepable_amount are equal, and the reason they are
      # not equal in general: here the rate rule allocates nothing, so the only claim on the
      # balance is the live bill, which both readers reserve.
      expect(calc(car).free_amount).to eq(0)
    end

    # The same shape with the anchored rule settled — a one-off dated Aug 1, now behind us. A
    # fulfilled bill reserves nothing, so the whole balance sweeps. Without this the examples
    # above pass against "any anchored rule reserves forever".
    #
    # The two figures still differ, by exactly $100, and that difference is correct: it is the
    # LIVE rate rule's allocation. #free_amount asks "what does no rule currently claim",
    # #sweepable_amount asks "what belongs to a period that is over".
    it "sweeps the whole balance once the anchored rule beside the rate rule is fulfilled", :aggregate_failures do
      car = envelope(name: "Car")
      rate = rule(car, :per_period_rate, amount: 100)
      settled = rule(car, :one_time, amount: 500)
      fund(car, 900, on: last_period)

      expect(calc(car).allocated_balances[settled]).to eq(0)
      expect(calc(car).allocated_balances[rate]).to eq(100)
      expect(calc(car).free_amount).to eq(800)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(900)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # A settled rule's own contribution cannot move, because BudgetCalculator#shortfall returns
    # `0.to_d` for a fulfilled rule BEFORE it looks at `allocated`, so the figure handed to it is
    # already ignored. Amply funded, so nothing behind it in the fill order changes either.
    it "does not change what a category asks for when the settled rule stops holding money" do
      car = envelope(name: "Car")
      rule(car, :per_period_rate, amount: 100)
      rule(car, :one_time, amount: 500)
      fund(car, 900, on: last_period)

      expect(calc(car).required).to eq(0)
    end

    # The redistribution, and the direction where #required DOES move. A settled one-off due Aug 1
    # sorts ahead of a live $400 bill due Sep 1, and the category holds only $300: the settled rule
    # takes nothing, the live bill gets the $300, and the category asks for the $100 it is actually
    # missing. Both allocations are pinned and they do not coincide ($0 vs $300), so the example
    # cannot pass on a fixture where the fill order happens not to matter.
    it "hands a settled rule's allocation to the live rule behind it", :aggregate_failures do
      car = envelope(name: "Car")
      settled = rule(car, :one_time, amount: 500)
      bill = rule(car, amount: 400, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(car, 300, on: last_period)

      expect(calc(car).allocated_balances[settled]).to eq(0)
      expect(calc(car).allocated_balances[bill]).to eq(300)
      expect(calc(car).required).to eq(100)
      expect(calc(car).required).to be_a(BigDecimal)
    end

    # The zero handed to a settled rule is summed by #reserve, so it is a BigDecimal, not a bare
    # `0` — the same guarantee #balance carries, at the one shape that produces nothing but
    # skipped rules.
    it "reserves a BigDecimal zero when every rule on the category is settled", :aggregate_failures do
      car = envelope(name: "Car")
      settled = rule(car, :one_time, amount: 500)
      fund(car, 900, on: last_period)

      expect(calc(car).allocated_balances[settled]).to be_a(BigDecimal)
      expect(calc(car).reserve).to eq(0)
      expect(calc(car).reserve).to be_a(BigDecimal)
      expect(calc(car).free_amount).to eq(900)
      expect(calc(car).free_amount).to be_a(BigDecimal)
    end

    # Mixed bases on one envelope: the per-period rule's period ended Aug 6, the monthly rule's
    # does not end until Aug 31. `all?` means the LATEST period governs, so the money stays put
    # while any rule still has a live claim on it.
    it "waits for the later period when an envelope mixes bases", :aggregate_failures do
      utilities = envelope(name: "Utilities")
      rule(utilities, :per_period_rate, amount: 100)
      rule(utilities, :rate, amount: 600)
      fund(utilities, 75, on: Date.new(2026, 8, 5))

      expect(utilities.budgets.map { |b| b.calculator(today: Date.new(2026, 8, 5)).period_end })
        .to contain_exactly(Date.new(2026, 8, 6), Date.new(2026, 8, 31))
      expect(calc(utilities).period_closed?).to be(false)
      expect(calc(utilities).sweepable_amount).to eq(0)
    end

    # The other direction of the same mixed-basis envelope: money from July is past both period
    # ends, so both rules agree and it sweeps.
    it "sweeps a mixed-basis envelope once every basis has rolled" do
      utilities = envelope(name: "Utilities")
      rule(utilities, :per_period_rate, amount: 100)
      rule(utilities, :rate, amount: 600)
      fund(utilities, 75, on: last_period)

      expect(calc(utilities).period_closed?).to be(true)
    end

    # No rate rule means no period to close. A category funded only against a dated bill
    # accumulates toward it; "use it or lose it" is a rate envelope's policy, not every
    # category's, and applying it here would empty the bill fund every month.
    #
    # Funded $600 against a $500 bill rather than exactly $500: at an exact match the reserve
    # would eat the balance and #sweepable_amount would read 0 either way; the extra $100 makes
    # both assertions bite, because a lost guard turns `[].all?` into `true` and hands that $100
    # to available.
    it "does not sweep a category with only anchored rules", :aggregate_failures do
      rent = envelope(name: "Rent")
      rule(rent, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(rent, 600, on: last_period)

      expect(calc(rent).balance).to eq(600)
      expect(calc(rent).period_closed?).to be(false)
      expect(calc(rent).sweepable_amount).to eq(0)
    end

    it "does not sweep a category with no rules at all", :aggregate_failures do
      mystery = envelope(name: "Mystery")
      fund(mystery, 80, on: last_period)

      expect(calc(mystery).period_closed?).to be(false)
      expect(calc(mystery).sweepable_amount).to eq(0)
    end

    # The emptiest shape in the app, and the one every money reader here has changed type on
    # before: no allocations and no entries, so every `sum(:amount)` behind #balance returns the
    # Integer literal 0.
    #
    # #period_closed? is asserted directly because the $0 balance cannot distinguish the
    # `last_funded_on.nil?` guard from the clamp: with nothing in the category, sweepable reads 0
    # whether the period is judged closed or not. This category has never been funded, so there is
    # no period for it to be past — the marker has to say so on its own.
    it "returns a BigDecimal zero for a category holding nothing", :aggregate_failures do
      fresh = envelope(name: "Fresh")
      rule(fresh, :per_period_rate, amount: 400)

      expect(calc(fresh).period_closed?).to be(false)
      expect(calc(fresh).sweepable_amount).to eq(0)
      expect(calc(fresh).sweepable_amount).to be_a(BigDecimal)
    end

    # A closed envelope that was overspent has nothing to give back. The deficit is available's
    # problem, and a negative sweep would be available paying the envelope on the way OUT — money
    # moving the wrong way through the ledger.
    it "sweeps nothing from a closed envelope that went negative", :aggregate_failures do
      dining = envelope(name: "Dining")
      rule(dining, :per_period_rate, amount: 150)
      fund(dining, 100, on: last_period)
      spend(dining, 180, on: last_period)

      expect(calc(dining).balance).to eq(-80)
      expect(calc(dining).period_closed?).to be(true)
      expect(calc(dining).sweepable_amount).to eq(0)
      expect(calc(dining).sweepable_amount).to be_a(BigDecimal)
    end

    # `net_of_sweep:` — what this category would need if the sweep had already happened. It exists
    # because #required reads the LIVE balance while the sweep is only materialised when the user
    # confirms the distribution, so a swept envelope's leftover is still sitting in it at the
    # moment it is asked what it needs.
    describe "net_of_sweep" do
      # The default is asserted as an EQUALITY WITH TODAY'S NUMBERS, not merely as "something
      # sensible": every caller in the app builds a calculator without this keyword, and the
      # keyword must be incapable of moving any of their figures. Then the same envelope with the
      # keyword, at figures that differ in both readers (balance 85 → 0, required 315 → 400), so
      # neither direction can pass on a coincidence.
      it "changes nothing unless it is asked for", :aggregate_failures do
        groceries = envelope(name: "Groceries")
        rule(groceries, :per_period_rate, amount: 400)
        fund(groceries, 85, on: last_period)

        expect(calc(groceries).balance).to eq(85)
        expect(calc(groceries).free_amount).to eq(0)
        expect(calc(groceries).required).to eq(315)
        expect(calc(groceries).sweepable_amount).to eq(85)

        post_sweep = groceries.holding_calculator(today: today, net_of_sweep: true)
        expect(post_sweep.balance).to eq(0)
        expect(post_sweep.required).to eq(400)
      end

      # The negative direction, at the same shape and the same $85: this money belongs to the live
      # period, so there is no sweep to net off and the flagged calculator must answer exactly what
      # the plain one does. Without this the example above passes against a keyword that simply
      # zeroes the balance.
      it "subtracts nothing from a category with nothing to sweep", :aggregate_failures do
        groceries = envelope(name: "Groceries")
        rule(groceries, :per_period_rate, amount: 400)
        fund(groceries, 85, on: this_period)

        post_sweep = groceries.holding_calculator(today: today, net_of_sweep: true)
        expect(calc(groceries).sweepable_amount).to eq(0)
        expect(post_sweep.balance).to eq(85)
        expect(post_sweep.required).to eq(315)
      end

      # The footgun, closed with code rather than with a comment. A flagged calculator does not
      # return zero from #sweepable_amount — it re-derives a SECOND, smaller sweep from what the
      # dated rules no longer hold, which on the mixed envelope below is a plausible-looking $100
      # after the real $400. A plausible number is what a committer cannot detect, so both readers
      # refuse outright. The same two readers are asserted on the PLAIN calculator over the same
      # category in the same example: a raise pinned in one direction only would pass just as well
      # against a class that raised for everyone.
      it "refuses to say what to sweep once the sweep is already netted off", :aggregate_failures do
        car = envelope(name: "Car")
        rule(car, :per_period_rate, amount: 100)
        rule(car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
        fund(car, 900, on: last_period)
        post_sweep = car.holding_calculator(today: today, net_of_sweep: true)

        expect(calc(car).sweepable_amount).to eq(400)
        expect(calc(car).period_closed?).to be(true)
        expect { post_sweep.sweepable_amount }.to raise_error(described_class::NetOfSweepError, /sweepable_amount/)
        expect { post_sweep.period_closed? }.to raise_error(described_class::NetOfSweepError, /period_closed\?/)
        # The reader it exists for still answers, on the very calculator that refuses the other.
        expect(post_sweep.required).to eq(100)
      end

      # The subtraction is the one place a BigDecimal balance meets a figure that could be a bare
      # Integer, and a category holding nothing is where every `sum(:amount)` behind it returns
      # the Integer literal 0.
      it "keeps the balance a BigDecimal on a category holding nothing", :aggregate_failures do
        fresh = envelope(name: "Fresh")
        rule(fresh, :per_period_rate, amount: 400)

        post_sweep = fresh.holding_calculator(today: today, net_of_sweep: true)
        expect(post_sweep.balance).to eq(0)
        expect(post_sweep.balance).to be_a(BigDecimal)
        expect(post_sweep.required).to be_a(BigDecimal)
      end
    end
  end

  # THE PRELOAD, PINNED AS A QUERY COUNT — the ruling carried out of Task 2's review, which found
  # `PoolCalculator#rules` preloading `[:item, :pool]` while its #required path walked the
  # now-populated CATEGORY arm of `Budget#user`. This port preloads `[:item, :category]`.
  #
  # Counted per TABLE rather than as a total, because the total is not O(1) and cannot be: each
  # dated rule runs its own paid-since-anchor SUM, which no preload can batch. What the preload is
  # responsible for is the item load and the owner walk, and those are one query each however many
  # rules there are.
  #
  # MEASURED IN BOTH DIRECTIONS on this fixture — six item-bearing dated rules, over a category
  # loaded fresh so nothing is warm:
  #
  #   * `[:item, :category]` — 18 statements, 1 items load, 1 users load
  #   * `[:category]` alone  — 23 statements, 6 items loads (BudgetCalculator#fulfilled? and
  #                            #overdue? read `budget.item` for every dated rule)
  #   * `[:item]` alone      — 18 statements, unchanged: reading the rules off `category.budgets`
  #                            means `has_many :budgets`' automatic `inverse_of` has already handed
  #                            each rule back the very category it came from, so `budget.user`
  #                            walks one shared Category and loads one User.
  #
  # So `:item` is what this line buys, and `:category` is kept on `PoolCalculator`'s stated reason
  # for keeping `:pool`: it costs nothing and it is the one thing standing between `Budget#user`'s
  # category arm and a lookup per rule if that inverse is ever lost. The users count is pinned
  # beside the items count for exactly that — it is the figure the review was about, and nothing
  # else in the suite would notice it going to six.
  describe "the rules preload" do
    let(:preload_user) { create(:user, :biweekly) }
    let(:today) { Date.new(2026, 8, 20) }

    def statements_for
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      yield
      statements
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "loads the items and the owners once each, however many dated rules there are", :aggregate_failures do
      bills = create(:category, :expense, :funded, user: preload_user, name: "Bills")
      6.times do |n|
        item = create(:item, category: bills, name: "Bill #{n}")
        rule(bills, item: item, amount: 100, interval_months: 6, anchor_date: Date.new(2026, 9, 1))
      end
      # Re-found rather than reused: the fixture's own object carries a loaded `user`, which would
      # answer the owner walk out of memory and hide the very lookup this pins.
      calc = Category.find(bills.id).holding_calculator(today: today)

      sql = statements_for { calc.required }

      expect(sql.grep(/FROM "items"/).size).to eq(1)
      expect(sql.grep(/FROM "users"/).size).to eq(1)
    end
  end
end
