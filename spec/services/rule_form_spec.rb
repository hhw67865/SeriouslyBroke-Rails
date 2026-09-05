# frozen_string_literal: true

require "rails_helper"

# ** THE ONE TYPED DOOR ONTO A RULE'S COLUMNS (rules-own-the-budget spec §4). **
#
# Every example below plants LITERALS on both sides: the words a person could actually choose on
# §4's form, and the exact columns §2.1's table says those words mean. That is the whole point of
# the file — the mapping is stated in a table in a spec document and in one method here, and a test
# that re-derived either from the other would agree with itself and with nothing else.
#
# THE ROUND TRIP IS ASSERTED FOR EVERY ROW OF §2.1, because `RuleForm.from` is what the EDIT form
# renders from: a reverse mapping that loses a column re-shapes a saved rule the moment somebody
# opens it, and does so silently.
RSpec.describe RuleForm do
  let(:user) { create(:user, :biweekly, typical_income: 2_400) }
  let!(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  # The words a bare form would submit with the radio left at its default, so each example below
  # states only the fields it is about.
  def words(**overrides)
    {
      category_id: groceries.id,
      rule_type: "usage",
      amount: "400",
      schedule: "per_period"
    }.merge(overrides)
  end

  def form(**overrides) = described_class.new(user, words(**overrides))

  # ** THREE COLUMNS WHERE THERE WERE FIVE (two-shapes spec §5/§7). ** `carries_over` and
  # `target_amount` are dropped, so what the words map onto is the CADENCE and nothing else.
  def columns_of(budget)
    {
      basis: budget.basis,
      interval_months: budget.interval_months,
      anchor_date: budget.anchor_date
    }
  end

  # ---------------------------------------------------------------------------------------------
  # The words → the columns: both schedules, and the checkbox that tells the dated pair apart
  # ---------------------------------------------------------------------------------------------
  describe "the columns each combination writes", :aggregate_failures do
    # §2 row 1 — the allowance that resets with the paycheck. The shape a hand-made rule means, and
    # the one the form opens on.
    it "writes a per-period rule" do
      expect(columns_of(form.budget)).to eq(basis: "per_period", interval_months: nil, anchor_date: nil)
    end

    # ** §2 rows 3 AND 5 ARE ONE COMBINATION, WHICH IS THE WHOLE OF WHAT THIS TASK CHANGED. ** "$600
    # by Dec 1" and "$5,000 by Jun 1, 2027" are a bill and a goal, and the form writes exactly the
    # same three columns for both: a `monthly` basis, NO interval, and the date. There is no
    # "unspent money" question left to ask, because a fund IS this shape.
    it "writes a by-date rule with no interval when it does not repeat" do
      form = form(schedule: "by_date", anchor_date: "2026-12-01", amount: "600")

      expect(columns_of(form.budget)).to eq(
        basis: "monthly", interval_months: nil, anchor_date: Date.new(2026, 12, 1)
      )
    end

    it "writes a goal as the same shape with a longer horizon" do
      form = form(schedule: "by_date", anchor_date: "2027-06-01", amount: "5000")

      expect(columns_of(form.budget)).to eq(
        basis: "monthly", interval_months: nil, anchor_date: Date.new(2027, 6, 1)
      )
    end

    # §2 row 4 — "$600 every 6 months from Dec 1". The checkbox is what adds the interval.
    it "writes an interval when the rule repeats" do
      form = form(schedule: "by_date", repeats: "1", interval_months: "6", anchor_date: "2026-12-01", amount: "600")

      expect(columns_of(form.budget)).to eq(
        basis: "monthly", interval_months: 6, anchor_date: Date.new(2026, 12, 1)
      )
    end

    # ** AN UNCHECKED BOX SUBMITS `"0"`, NOT NOTHING, and a truthiness test would read it as ticked. **
    # `ActiveModel::Type::Boolean` is the same cast a boolean column applies, which is why
    # `#repeats?` uses it — without it a one-off would silently carry an interval.
    it "writes no interval when the box submits an unchecked zero" do
      form = form(schedule: "by_date", repeats: "0", interval_months: "6", anchor_date: "2026-12-01")

      expect(form.budget.interval_months).to be_nil
    end

    # ** THE INTERVAL IS IGNORED ON A PER-PERIOD RULE ONLY WHERE THE FORM NEVER OFFERED IT. ** It is
    # REFUSED here rather than dropped — see "where the errors land" — because dropping it would
    # change when the money is needed. This example is the checkbox's own arm: `repeats` off means
    # the control is not on screen, so its number is not an opinion.
    it "leaves a per-period rule with neither date nor interval" do
      form = form(schedule: "per_period", repeats: "1", interval_months: "6")

      expect(columns_of(form.budget)).to eq(basis: "per_period", interval_months: nil, anchor_date: nil)
    end

    # `item_id` BLANK IS THE WHOLE CATEGORY, and blank means blank rather than "".
    it "leaves the item blank for a rule that pays the whole category" do
      expect(form(item_id: "").budget.item_id).to be_nil
    end

    it "names the item a rule pays" do
      phone = create(:item, category: groceries, name: "Phone")

      expect(form(item_id: phone.id).budget.item_id).to eq(phone.id)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The columns → the words: the edit form's own reading, round-tripped
  # ---------------------------------------------------------------------------------------------
  describe ".from" do
    # EVERY ROW OF §2 THE FORM CAN WRITE, AND THE ASSERTION IS THE FULL ROUND TRIP: the words this
    # reads off a rule, fed back through the form, must land on the columns it started from. A
    # reverse mapping that loses one of them re-shapes a saved rule the moment its edit form is
    # opened, with no save and no message.
    #
    # ** THE MONTHLY-NO-ANCHOR ROW IS DELIBERATELY ABSENT FROM THIS TABLE, and it has an example of
    # its own two below: it is the ONE row that does not round-trip, by ruling rather than by
    # accident. **
    {
      "a per-period rule" => { basis: :per_period, interval_months: nil },
      "a rule every 6 months from a date" => {
        basis: :monthly, interval_months: 6, anchor_date: Date.new(2026, 12, 1)
      },
      "a monthly rule WITH a date" => {
        basis: :monthly, interval_months: 1, anchor_date: Date.new(2026, 12, 1)
      },
      "a one-time bill" => { basis: :monthly, interval_months: nil, anchor_date: Date.new(2026, 12, 1) },
      "a goal" => { basis: :monthly, interval_months: nil, anchor_date: Date.new(2027, 6, 1) }
    }.each do |name, attributes|
      it "round-trips #{name}" do
        rule = create(:budget, **attributes, category: groceries, amount: 600, rule_type: :choice)
        before = columns_of(rule)

        rebuilt = described_class.new(user, described_class.from(rule)).budget

        expect(columns_of(rebuilt)).to eq(before)
      end
    end

    # A MONTHLY BILL WITH A DUE DATE REPEATS WITH AN N OF 1, and that is not the same question
    # `Budget#cadence` answers. `#cadence` calls that shape `:monthly` because it is saying what a
    # PERIOD of the rule is; this is saying which controls the user set, and the two part company on
    # exactly this row — the suggestion panel's own proposed bills are all of it.
    it "reads a dated monthly rule as repeating, with the N it carries", :aggregate_failures do
      rule = build(:budget, basis: :monthly, interval_months: 1, anchor_date: Date.new(2026, 12, 1))

      expect(described_class.from(rule)).to include(schedule: "by_date", repeats: true, interval_months: 1)
    end

    # ** AN ANCHORLESS `monthly` ROW READS BACK AS "Every period", AND THE SHAPE DOES NOT SURVIVE A
    # SAVE (two-shapes §5's ruling). ** "$260 every month" with no due date is a legal row and
    # `SuggestionEngine` still writes one; the form's two options do not include it, so opening such a
    # rule and saving it unchanged CONVERTS it to a per-period rate stated in the same figure. That is
    # the ruling taken rather than a defect hidden — the shape stays reachable for existing rows and
    # for the engine, it is not offered, and the second option covers what people actually write.
    #
    # BOTH HALVES ARE ASSERTED, so neither "it reads back as something else" nor "the conversion is
    # silent" can change without this example saying so.
    it "reads an anchorless monthly rule back as per-period, and converts it on save", :aggregate_failures do
      rule = create(:budget, :rate, category: groceries, amount: 260)

      expect(described_class.from(rule)).to include(schedule: "per_period", repeats: false, interval_months: nil)

      rebuilt = described_class.new(user, described_class.from(rule), budget: rule)

      expect(rebuilt.save).to be true
      expect(columns_of(rule.reload)).to eq(basis: "per_period", interval_months: nil, anchor_date: nil)
      expect(rule.amount).to eq(260)
    end

    # ** AND IT CARRIES A FLAG SAYING SO, BECAUSE THE CONVERSION IS NOT FREE (fix round 1 — MED-5). **
    # `#apply_to_budget` writes `basis: per_period` onto the record in the CONSTRUCTOR, so by the
    # time a view renders it the row says per-period while the figure in the box is still a month's —
    # and `Budget#steady_ask` prices $260 a month at `260 × 12 ÷ 26` = **$120.00** a fortnight, so
    # saving it unchanged multiplies what the rule really costs by 2.17×. The flag is what lets the
    # form say the amount in the ROW's unit and warn about the save.
    #
    # BOTH DIRECTIONS, because a flag that was always true would read the same on this example.
    it "flags the monthly read-back, and only that one", :aggregate_failures do
      monthly = create(:budget, :rate, category: groceries, amount: 260)
      per_period = create(:budget, :per_period_rate, category: create(:category, :expense, :funded, user: user), amount: 400)

      expect(described_class.from(monthly)).to include(converted_from_monthly: true)
      # ABSENT RATHER THAN `false`, on `interval_months`' own convention: `SuggestionEngine` puts
      # these words on an accept URL through `.compact`, and a `false` would ride in every query
      # string the panel builds to say nothing.
      expect(described_class.from(per_period)[:converted_from_monthly]).to be_nil
      expect(described_class.new(user, described_class.from(monthly), budget: monthly).amount_unit).to eq("a month")
      expect(described_class.new(user, described_class.from(per_period), budget: per_period).amount_unit).to be_nil
    end

    # ** THE WIRE CANNOT SET IT. ** It is a fact about the ROW, not an answer the user gave, so it is
    # absent from `BudgetsController::BUDGET_FIELDS` and a hand-made POST that names it is dropped
    # before this class ever sees it — which is what keeps a form from claiming a conversion that is
    # not happening.
    it "is not one of the fields the form submits", :aggregate_failures do
      expect(described_class::FIELDS).not_to include(:converted_from_monthly)
      expect(BudgetsController::BUDGET_FIELDS).not_to include(:converted_from_monthly)
    end

    # NO INTERVAL IS HANDED BACK WHERE THE CHECKBOX IS OFF, because the control is not on screen and
    # a value in it is a value the user never typed — which `#check_interval` then refuses.
    it "hands back no interval for a one-off", :aggregate_failures do
      rule = build(:budget, :by_date)

      expect(described_class.from(rule)).to include(schedule: "by_date", repeats: false, interval_months: nil)
    end

    # THE DATE IS NAMED BY THE EXAMPLE rather than taken from the trait's own default, which is
    # relative to `Date.current` since fix round 1 (LOW-9) — a fixed literal here would be asserting
    # the factory's clock rather than the mapping.
    it "reads a goal's amount, its date and its type", :aggregate_failures do
      rule = build(:budget, :by_date, rule_type: :choice, amount: 5_000, due: Date.new(2027, 6, 1))

      expect(described_class.from(rule)).to include(
        schedule: "by_date", anchor_date: Date.new(2027, 6, 1), rule_type: "choice", amount: 5_000
      )
    end
  end

  # ---------------------------------------------------------------------------------------------
  # Where a refusal lands — the control that chose, never a column the form does not render
  # ---------------------------------------------------------------------------------------------
  describe "where the errors land", :aggregate_failures do
    # THE SHAPE ERRORS BELONG TO "HOW OFTEN". `Budget` states them on `basis`, `interval_months` and
    # `anchor_date`, none of which is a control on §4's form — an error on an attribute the form
    # does not render produces a 422 whose only visible text is "please review the problems below".
    it "refuses a per-period rule carrying a due date, under How often" do
      form = form(anchor_date: "2026-12-01")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/does not take a due date/)
      expect(form.errors[:anchor_date]).to be_empty
    end

    it "refuses a per-period rule carrying a number of months, under How often" do
      form = form(interval_months: "6")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/does not take a number of months/)
    end

    # THE CHECKBOX IS WHAT REVEALS THE INTERVAL, so a number typed with the box off is a choice the
    # user did not make.
    it "refuses a number of months on a by-date rule that does not repeat" do
      form = form(schedule: "by_date", anchor_date: "2026-12-01", interval_months: "3")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/does not take a number of months/)
    end

    # `shape_must_be_valid` RETURNS EARLY ON ANY ANCHORED RULE, so a blank N with a date is a valid
    # `Budget` — it is a one-time rule. It is not the rule the user described, which is why this
    # question is the FORM's and not the model's.
    it "refuses a repeating rule with no N, under When it is needed" do
      form = form(schedule: "by_date", repeats: "1", anchor_date: "2026-12-01", interval_months: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the number of months/)
    end

    it "refuses a repeating rule with no date, under When it is needed" do
      form = form(schedule: "by_date", repeats: "1", interval_months: "6", anchor_date: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the date it is first due/)
    end

    it "refuses a one-off with no date, under When it is needed" do
      form = form(schedule: "by_date", anchor_date: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the date it is first due/)
    end

    # AN N OF ZERO IS `Budget`'s OWN REFUSAL, re-keyed: `interval_months` numericality lands on the
    # column, and the column is a consequence of "When is it needed?".
    it "carries a zero interval onto When it is needed" do
      form = form(schedule: "by_date", repeats: "1", interval_months: "0", anchor_date: "2026-12-01")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/greater than 0/)
    end

    it "keeps an amount error on the amount" do
      form = form(amount: "")

      expect(form.save).to be false
      expect(form.errors[:amount]).to include(/can't be blank/)
    end

    # ZERO IS LEGAL ON EXACTLY ONE SHAPE, so on every other one it is an error about the AMOUNT and
    # not about the target.
    it "refuses a zero amount on a rule that resets" do
      form = form(amount: "0")

      expect(form.save).to be false
      expect(form.errors[:amount]).to include(/greater than 0/)
    end

    # EVERY RULE HAS A TYPE (§3), and the radio is not preselected on a hand-made rule — the
    # give-way order is built on this answer, so a form that guessed it would be answering for the
    # user.
    it "refuses a rule with no type, under Type" do
      form = form(rule_type: "")

      expect(form.save).to be false
      expect(form.errors[:rule_type]).to include(/can't be blank/)
    end

    it "refuses a type that is not one of the three" do
      form = form(rule_type: "luxury")

      expect(form.save).to be false
      expect(form.errors[:rule_type]).to include(/is not a kind of rule/)
    end

    it "refuses a schedule that is not one of the four" do
      form = form(schedule: "fortnightly")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/is not one of the choices/)
    end

    # ** THE CATCH-ALL RULE IS `Budget`'s ONE `:base` MESSAGE THAT IS REALLY ABOUT A CONTROL. ** Its
    # own second half — "or point this rule at a single item" — IS the "Pays" select, so it lands
    # there rather than in the form's banner. Routed by `Budget::CATCH_ALL_TAKEN`'s identity, so a
    # rewording cannot quietly send it back to `:base`.
    it "puts a second catch-all rule under Pays" do
      create(:budget, :per_period_rate, category: groceries, amount: 200)
      form = form(item_id: "")

      expect(form.save).to be false
      expect(form.errors[:item_id]).to include(Budget::CATCH_ALL_TAKEN)
      expect(form.errors[:base]).to be_empty
    end

    # THE OTHER `:base` MESSAGE STAYS ON `:base`, because an owner-less rule really is a fact about
    # the whole record — the form prints base errors in its own notification.
    it "leaves an owner-less rule on the record itself" do
      form = form(category_id: "")

      expect(form.save).to be false
      expect(form.errors[:base]).to include(/must belong to a category/)
    end

    # RE-PARENTING ONTO AN INCOME CATEGORY IS THE UPDATE PATH'S OWN REFUSAL. `Budget`'s
    # `category_must_be_an_expense` is stated on `:category`, which is not a control — the form's is
    # `category_id` — and on an EDIT the category is a read-only box, so the form lifts it into the
    # banner from there.
    it "puts an income category under the category control" do
      income = create(:category, :income, user: user)
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)
      form = described_class.new(user, words(category_id: income.id), budget: rule)

      expect(form.save).to be false
      expect(form.errors[:category_id]).to include(/must be an expense category/)
      expect(rule.reload.category).to eq(groceries)
    end

    # THE CREATE PATH IS REFUSED A STEP EARLIER AND SOMEWHERE ELSE: `BudgetProposal` stamps
    # `funded_since` first, `Category#only_expenses_hold_money` refuses that on an income category,
    # and the refusal arrives as a `:base` message about the CATEGORY rather than about a column of
    # the rule. It belongs in the banner, which is where `:base` goes.
    it "puts a new rule on an income category in the banner" do
      income = create(:category, :income, user: user)
      form = form(category_id: income.id)

      expect(form.save).to be false
      expect(form.errors[:base]).to include(/only expense categories hold money/)
      expect(income.reload.funded_since).to be_nil
    end

    it "puts an item from another category under Pays" do
      elsewhere = create(:item, category: create(:category, :expense, :funded, user: user), name: "Fuel")
      form = form(item_id: elsewhere.id)

      expect(form.save).to be false
      expect(form.errors[:item_id]).to include(/must belong to this category/)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # What #save actually writes
  # ---------------------------------------------------------------------------------------------
  describe "#save", :aggregate_failures do
    # A RULE IS ONE OF THE TWO THINGS THAT MAKE A CATEGORY START HOLDING MONEY (two-ledger §4), and
    # `BudgetProposal` is the one writer of that pair. The form goes through it on the create path.
    it "starts an unfunded category holding money" do
      coffee = create(:category, :expense, user: user, name: "Coffee")
      form = form(category_id: coffee.id)

      expect(form.save).to be true
      expect(coffee.reload.funded_since).to eq(Date.current)
    end

    it "writes nothing when the rule is refused" do
      expect { form(amount: "").save }.not_to change(Budget, :count)
    end

    # ** A SHAPE CHANGE ON AN EXISTING RULE IS LEGAL (§5). ** The claim is computed, so the walk
    # simply re-runs from the rule's accrual start under the new shape — `#claim_shape` is the one
    # door onto that reading and it answers the new shape immediately.
    it "changes an allowance into a goal", :aggregate_failures do
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)
      form = described_class.new(user, words(schedule: "by_date", anchor_date: "2027-06-01", amount: "5000"), budget: rule)

      expect(form.save).to be true
      expect(columns_of(rule.reload))
        .to eq(basis: "monthly", interval_months: nil, anchor_date: Date.new(2027, 6, 1))
      expect(rule.claim_shape).to eq(:dated)
    end

    # AND BACK THE OTHER WAY, date and all: a goal that becomes an ordinary allowance must not leave
    # a date behind that would go on making it a fund.
    it "changes a goal back into an allowance", :aggregate_failures do
      rule = create(:budget, :by_date, category: groceries, amount: 5_000)
      form = described_class.new(user, words(schedule: "per_period", amount: "200"), budget: rule)

      expect(form.save).to be true
      expect(columns_of(rule.reload)).to eq(basis: "per_period", interval_months: nil, anchor_date: nil)
      expect(rule.claim_shape).to eq(:rate)
    end

    # And a one-off given the checkbox picks up its interval, which is the only difference between
    # §2's rows 3 and 4.
    it "changes a one-off into a repeating bill", :aggregate_failures do
      rule = create(:budget, :by_date, category: groceries, amount: 600)
      repeating = words(schedule: "by_date", repeats: "1", interval_months: "6", anchor_date: "2026-12-01", amount: "600")

      expect(described_class.new(user, repeating, budget: rule).save).to be true
      expect(columns_of(rule.reload))
        .to eq(basis: "monthly", interval_months: 6, anchor_date: Date.new(2026, 12, 1))
      expect(rule.claim_shape).to eq(:dated)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The collections the form renders
  # ---------------------------------------------------------------------------------------------
  describe "the collections", :aggregate_failures do
    it "offers this user's expense categories and nothing else" do
      create(:category, :income, user: user, name: "Salary")
      create(:category, :expense, :funded, user: create(:user), name: "Their Rent")

      expect(form.category_options.map(&:name)).to eq(["Groceries"])
    end

    # EVERY ITEM AT ONCE, because the "Pays" select is filtered in the browser: the options for a
    # category the user has not chosen yet still have to be in the document for the filter to reveal
    # them without a round trip.
    it "offers every item of every expense category the user owns" do
      create(:item, category: groceries, name: "Phone")
      other = create(:category, :expense, :funded, user: user, name: "Utilities")
      create(:item, category: other, name: "Power")
      create(:item, category: create(:category, :income, user: user), name: "Bonus")
      create(:item, category: create(:category, :expense, :funded, user: create(:user)), name: "Their Item")

      expect(form.item_options.map(&:name)).to eq(["Phone", "Power"])
    end
  end
end
