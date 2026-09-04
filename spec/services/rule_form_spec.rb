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

  # The words a bare form would submit with the two radios left at their defaults, so each example
  # below states only the fields it is about.
  def words(**overrides)
    {
      category_id: groceries.id,
      rule_type: "usage",
      amount: "400",
      schedule: "per_period",
      unspent: "resets"
    }.merge(overrides)
  end

  def form(**overrides) = described_class.new(user, words(**overrides))

  def columns_of(budget)
    {
      basis: budget.basis,
      interval_months: budget.interval_months,
      anchor_date: budget.anchor_date,
      carries_over: budget.carries_over,
      target_amount: budget.target_amount
    }
  end

  # ---------------------------------------------------------------------------------------------
  # The words → the columns: every schedule against every unspent choice
  # ---------------------------------------------------------------------------------------------
  describe "the columns each combination writes", :aggregate_failures do
    # §2.1 row 1 — groceries. The shape a hand-made rule means, and the one the form opens on.
    it "writes a per-period rule that resets" do
      expect(columns_of(form.budget)).to eq(
        basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: false, target_amount: nil
      )
    end

    # §2.1 row 2 — the emergency fund, uncapped. A blank target is a DECLARATION ("allow it to
    # infinitely grow"), not an omission, so it must reach the column as nil rather than as a refusal.
    it "writes a per-period rule that builds up with no cap" do
      expect(columns_of(form(unspent: "builds", target_amount: "").budget)).to eq(
        basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: nil
      )
    end

    # §2.1 row 3 — the vacation goal.
    it "writes a per-period rule that builds toward a target" do
      expect(columns_of(form(unspent: "builds", target_amount: "5000", amount: "200").budget)).to eq(
        basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: 5_000
      )
    end

    # §2.1 row 4 — the goal fed by hand. Zero is legal on exactly this shape
    # (`Budget#set_aside_only?`), and the form has to be able to reach it.
    it "writes a $0 rule that builds toward a target" do
      form = form(unspent: "builds", target_amount: "5000", amount: "0")

      expect(form.save).to be true
      expect(columns_of(form.budget)).to eq(
        basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: 5_000
      )
      expect(form.budget.amount).to eq(0)
    end

    # §2.1 row 5 — "$260 a month". THE INTERVAL OF 1 IS DERIVED AND NOT ASKED FOR: `monthly` is
    # `shape_must_be_valid`'s row 2, which pins an anchorless monthly rule to exactly one month.
    it "writes a monthly rule that resets, with an interval of one it was never given" do
      expect(columns_of(form(schedule: "monthly", amount: "260").budget)).to eq(
        basis: "monthly", interval_months: 1, anchor_date: nil, carries_over: false, target_amount: nil
      )
    end

    it "writes a monthly rule that builds up" do
      expect(columns_of(form(schedule: "monthly", unspent: "builds", target_amount: "1200").budget)).to eq(
        basis: "monthly", interval_months: 1, anchor_date: nil, carries_over: true, target_amount: 1_200
      )
    end

    # §2.1 row 6 — "$600 every 6 months from Dec 1".
    it "writes a rule that comes round every N months from a date" do
      form = form(schedule: "every_n", interval_months: "6", anchor_date: "2026-12-01", amount: "600")

      expect(columns_of(form.budget)).to eq(
        basis: "monthly",
        interval_months: 6,
        anchor_date: Date.new(2026, 12, 1),
        carries_over: false,
        target_amount: nil
      )
    end

    # §2.1 row 7 — "$600 once on Dec 1". A NULL interval beside a date is what makes it one-time;
    # there is no one-time concept beyond that (§1).
    it "writes a one-time rule as a date with no interval" do
      form = form(schedule: "once", anchor_date: "2026-12-01", amount: "600")

      expect(columns_of(form.budget)).to eq(
        basis: "monthly",
        interval_months: nil,
        anchor_date: Date.new(2026, 12, 1),
        carries_over: false,
        target_amount: nil
      )
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
  # `unspent` is a RADIO with a default, so on a dated schedule it is ignored rather than refused
  # ---------------------------------------------------------------------------------------------
  describe "a dated schedule and the unspent radio", :aggregate_failures do
    # A DATED RULE'S BUILD-UP IS DEFINED BY ITS DATE — §3.2's catch-up walk holds the money until
    # the bill is paid — and `Budget#build_up_must_be_valid` refuses the pair outright. The control
    # is not on screen for these two schedules, so the value it would have carried is not an
    # opinion; forcing `resets` is what stops a hidden default from producing a 422 about a radio
    # nobody saw.
    it "forces resets on an every-N-months rule, whatever the radio said" do
      form = form(schedule: "every_n", interval_months: "6", anchor_date: "2026-12-01", unspent: "builds")

      expect(form.save).to be true
      expect(form.budget.carries_over).to be false
    end

    it "forces resets on a one-time rule, whatever the radio said" do
      form = form(schedule: "once", anchor_date: "2026-12-01", unspent: "builds")

      expect(form.save).to be true
      expect(form.budget.carries_over).to be false
    end

    it "clears a target left on an every-N-months rule" do
      form = form(schedule: "every_n", interval_months: "6", anchor_date: "2026-12-01", target_amount: "5000")

      expect(form.save).to be true
      expect(form.budget.target_amount).to be_nil
    end

    # ** THE OTHER HALF OF THE SAME RULING, AND IT IS THE ONE A CHANGE OF MIND GOES THROUGH. ** The
    # radio and the field it reveals are ONE control, so "resets" is a complete answer about both:
    # a figure typed under "builds up" and left behind when the radio moved is cleared rather than
    # refused, because there is exactly one reading of it. `anchor_date` gets the opposite treatment
    # three examples down, and the difference is that a due date has no such reading.
    it "clears the target when the money resets" do
      form = form(unspent: "resets", target_amount: "5000")

      expect(form.save).to be true
      expect(form.budget.target_amount).to be_nil
      expect(form.budget.carries_over).to be false
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The columns → the words: the edit form's own reading, round-tripped
  # ---------------------------------------------------------------------------------------------
  describe ".from" do
    # EVERY ROW OF §2.1, AND THE ASSERTION IS THE FULL ROUND TRIP: the words this reads off a rule,
    # fed back through the form, must land on the columns it started from. A reverse mapping that
    # loses one of them re-shapes a saved rule the moment its edit form is opened, with no save and
    # no message.
    {
      "a per-period rule that resets" => { basis: :per_period, interval_months: nil },
      "a per-period rule that builds up" => { basis: :per_period, interval_months: nil, carries_over: true },
      "a per-period rule with a target" => {
        basis: :per_period, interval_months: nil, carries_over: true, target_amount: 5_000
      },
      "a monthly rule that resets" => { basis: :monthly, interval_months: 1 },
      "a monthly rule that builds up" => { basis: :monthly, interval_months: 1, carries_over: true },
      "a rule every 6 months from a date" => {
        basis: :monthly, interval_months: 6, anchor_date: Date.new(2026, 12, 1)
      },
      "a monthly rule WITH a date" => {
        basis: :monthly, interval_months: 1, anchor_date: Date.new(2026, 12, 1)
      },
      "a one-time rule" => { basis: :monthly, interval_months: nil, anchor_date: Date.new(2026, 12, 1) }
    }.each do |name, attributes|
      it "round-trips #{name}" do
        rule = create(:budget, **attributes, category: groceries, amount: 600, rule_type: :choice)
        before = columns_of(rule)

        rebuilt = described_class.new(user, described_class.from(rule)).budget

        expect(columns_of(rebuilt)).to eq(before)
      end
    end

    # A MONTHLY BILL WITH A DUE DATE IS "EVERY N MONTHS" WITH N OF 1, and that is not the same
    # question `Budget#cadence` answers. `#cadence` calls that shape `:monthly` because it is saying
    # what a PERIOD of the rule is; this is saying which control the user set, and the two part
    # company on exactly this row — the suggestion panel's own proposed bills are all of it.
    it "reads a dated monthly rule as every N months, with the N it carries" do
      rule = build(:budget, basis: :monthly, interval_months: 1, anchor_date: Date.new(2026, 12, 1))

      expect(described_class.from(rule)).to include(schedule: "every_n", interval_months: 1)
    end

    # AND THE ANCHORLESS ONE HANDS BACK NO INTERVAL AT ALL. The 1 on that row is DERIVED — nobody
    # typed it — so handing it back would fill a control that is not on screen, which the form then
    # refuses as a number of months a monthly rule does not take.
    it "hands back no interval for an anchorless monthly rule" do
      rule = build(:budget, :rate)

      expect(described_class.from(rule)).to include(schedule: "monthly", interval_months: nil)
    end

    it "reads a building rule's target and its type", :aggregate_failures do
      rule = build(:budget, :capped, rule_type: :choice, amount: 200)

      expect(described_class.from(rule)).to include(
        unspent: "builds", target_amount: 1_200, rule_type: "choice", amount: 200
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

    # THE MONTHLY ROW DERIVES ITS OWN INTERVAL, so a number typed beside it is a choice the user did
    # not make — `every N months` is the control that takes one.
    it "refuses a number of months on the monthly row" do
      form = form(schedule: "monthly", interval_months: "3")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/does not take a number of months/)
    end

    # `shape_must_be_valid` RETURNS EARLY ON ANY ANCHORED RULE, so a blank N with a date is a valid
    # `Budget` — it is a one-time rule. It is not the rule the user described, which is why this
    # question is the FORM's and not the model's.
    it "refuses every N months with no N, under How often" do
      form = form(schedule: "every_n", anchor_date: "2026-12-01", interval_months: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the number of months/)
    end

    it "refuses every N months with no date, under How often" do
      form = form(schedule: "every_n", interval_months: "6", anchor_date: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the date it is first due/)
    end

    it "refuses a one-time rule with no date, under How often" do
      form = form(schedule: "once", anchor_date: "")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/needs the date it is first due/)
    end

    # AN N OF ZERO IS `Budget`'s OWN REFUSAL, re-keyed: `interval_months` numericality lands on the
    # column, and the column is a consequence of "How often".
    it "carries a zero interval onto How often" do
      form = form(schedule: "every_n", interval_months: "0", anchor_date: "2026-12-01")

      expect(form.save).to be false
      expect(form.errors[:schedule]).to include(/greater than 0/)
    end

    # `Budget`'s own numericality on the column, landing on the same control.
    it "carries a target of zero onto Unspent money" do
      form = form(unspent: "builds", target_amount: "0")

      expect(form.save).to be false
      expect(form.errors[:unspent]).to include(/greater than 0/)
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

    # ** A SHAPE CHANGE ON AN EXISTING RULE IS LEGAL (§4). ** The claim is computed, so the walk
    # simply re-runs from the rule's accrual start under the new shape — `#claim_shape` is the one
    # door onto that reading and it answers the new shape immediately.
    it "changes a rate rule into a building one" do
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)
      form = described_class.new(user, words(unspent: "builds", target_amount: "5000"), budget: rule)

      expect(form.save).to be true
      expect(rule.reload.carries_over).to be true
      expect(rule.target_amount).to eq(5_000)
      expect(rule.claim_shape).to eq(:building)
    end

    # AND BACK THE OTHER WAY, target and all: a fund that becomes an ordinary rate rule must not
    # leave a figure behind that no formula reads.
    it "changes a building rule back into a rate rule" do
      rule = create(:budget, :capped, category: groceries, amount: 200)
      form = described_class.new(user, words(unspent: "resets", amount: "200"), budget: rule)

      expect(form.save).to be true
      expect(rule.reload.carries_over).to be false
      expect(rule.target_amount).to be_nil
      expect(rule.claim_shape).to eq(:rate)
    end

    # The dated direction of the same fact — a rate rule given a date drops the build-up columns
    # rather than carrying a `carries_over` the model would refuse beside an anchor.
    it "changes a rate rule into a dated bill" do
      rule = create(:budget, :building, category: groceries, amount: 300)
      dated = words(schedule: "every_n", interval_months: "6", anchor_date: "2026-12-01", amount: "600")

      expect(described_class.new(user, dated, budget: rule).save).to be true
      expect(columns_of(rule.reload)).to eq(basis: "monthly", interval_months: 6, anchor_date: Date.new(2026, 12, 1), carries_over: false, target_amount: nil)
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
