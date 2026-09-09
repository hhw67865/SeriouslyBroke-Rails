# frozen_string_literal: true

require "rails_helper"

# The user is biweekly, anchored on today, so the period edges are exact and every window below
# can be named as a date rather than derived. Complete periods, oldest last six:
#
#   P0  2025-11-14 .. 2025-11-27
#   P1  2025-11-28 .. 2025-12-11
#   P2  2025-12-12 .. 2025-12-25     drift window opens here
#   P3  2025-12-26 .. 2026-01-08     dead window opens here
#   P4  2026-01-09 .. 2026-01-22
#   P5  2026-01-23 .. 2026-02-05
#   --  2026-02-06 .. is the CURRENT period and is in no window
RSpec.describe SuggestionEngine do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: today) }
  let(:today) { Date.new(2026, 2, 6) }

  # WELL BEFORE EVERY ENTRY IN THIS FILE, AND A LITERAL RATHER THAN THE `:funded` TRAIT'S
  # `1.year.ago`. `CategoryLedger::ENTRY_CATEGORY_ID` counts an entry against a category only from
  # `funded_since` onward, and this file's history is fixed at late 2025 while `1.year.ago` walks
  # with the wall clock — so the trait's date would slide past the oldest entries one real year from
  # now and quietly empty the drift window. The same class of flake CLAUDE.md's third cause names.
  let(:holding_since) { Date.new(2024, 1, 1) }

  def engine(for_user: user, on: today) = described_class.new(user: for_user, today: on)

  def suggestions(...) = engine(...).suggestions

  def of_kind(kind, ...) = suggestions(...).select { |suggestion| suggestion.kind == kind }

  # A CATEGORY THAT HOLDS NOTHING — the rate detector's population (two-ledger spec §3/§4), and the
  # shape whose proposals start a category holding money. It was spelled "no pool at all" and then
  # "pointing at an account" while an envelope was what reserved money; `funded_since IS NULL` is
  # the same set said in the model that replaced both, and the factory leaves the column nil.
  def category(name) = create(:category, :expense, user: user, name: name)

  # A CATEGORY THAT DOES HOLD MONEY — what an envelope was. Its spending drains itself rather than
  # available, which is what makes it a drift lane and keeps it out of the rate population.
  def funded_category(name)
    create(:category, :expense, user: user, name: name, funded_since: holding_since)
  end

  def item(name, in_category:) = create(:item, category: in_category, name: name)

  def spend(on_item, amount, on:) = create(:entry, item: on_item, amount: amount, date: on)

  # Two items in one category, each paid twice a month apart — the shape "gives two bills in one
  # category the same owner" needs, pulled out only to keep that example under the line cap.
  def two_dated_bills(category, amount:)
    ["Phone", "Internet"].each_with_index do |name, index|
      bill = item(name, in_category: category)
      spend(bill, amount + index, on: Date.new(2025, 11, 20))
      spend(bill, amount + index, on: Date.new(2025, 12, 20))
    end
  end

  # One spend in each of P3, P4 and P5 — the three most recent complete periods. `amounts` may be
  # one figure for all three or one per period.
  def in_last_three_periods(on_item, amounts)
    [Date.new(2025, 12, 30), Date.new(2026, 1, 12), Date.new(2026, 1, 26)]
      .zip(Array(amounts).cycle.first(3))
      .each { |on, amount| spend(on_item, amount, on: on) }
  end

  # One spend in each of P2, P3, P4 and P5 — the whole drift window.
  def in_drift_window(on_item, amount)
    [Date.new(2025, 12, 20), Date.new(2026, 1, 2), Date.new(2026, 1, 15), Date.new(2026, 1, 29)]
      .each { |on| spend(on_item, amount, on: on) }
  end

  # An item that already carries a rule of its own — the state that stops dated-bill firing and
  # that amendment A subtracts from a category's drift spend. IN THE RULE'S OWN CATEGORY, because
  # `Budget#item_must_belong_to_category` says so and because the category IS the lane now: the
  # pool era put this item in a second category pointing at the same pool, which is the same
  # arrangement one layer out.
  def claimed_item(name, category:, amount: 500, **rule)
    owned = item(name, in_category: category)
    create(:budget, category: category, item: owned, amount: amount, **rule)
    owned
  end

  # ONE OF EVERY KIND, with the amounts ASCENDING in kind order — so a sort by size alone would
  # produce the exact reverse of the answer, and a sort by kind alone could not order ties. Also the
  # fixture the query count is pinned on, because it exercises every read the engine makes.
  def one_of_each
    water = item("Water", in_category: category("Bills"))
    spend(water, 120, on: Date.new(2025, 11, 10))
    spend(water, 120, on: Date.new(2025, 12, 10))

    beans = item("Beans", in_category: category("Coffee"))
    in_last_three_periods(beans, 150)

    groceries = funded_category("Groceries")
    create(:budget, :per_period_rate, category: groceries, amount: 100)
    in_drift_window(item("Food", in_category: groceries), 200)

    netflix = funded_category("Netflix")
    backed = claimed_item("Netflix", category: netflix, amount: 250, basis: :per_period, interval_months: nil)
    spend(backed, 250, on: Date.new(2025, 11, 20))
  end

  def query_count
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].to_s.in?(["SCHEMA", "TRANSACTION"])
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  describe "the empty and undeclared states" do
    it "is empty for a user who has declared no period, however much history they have" do
      undeclared = create(:user)
      bill = create(:item, category: create(:category, :expense, user: undeclared, name: "Bills"))
      create(:entry, item: bill, amount: 400, date: Date.new(2025, 11, 10))
      create(:entry, item: bill, amount: 400, date: Date.new(2025, 12, 10))

      expect(described_class.new(user: undeclared, today: today).suggestions).to eq([])
    end

    it "is empty for a declared user with no history and no rules" do
      expect(suggestions).to eq([])
    end

    it "does not see another user's history" do
      stranger = create(:user, period_cadence: :biweekly, period_anchor_date: today)
      theirs = create(:item, category: create(:category, :expense, user: stranger, name: "Theirs"))
      create(:entry, item: theirs, amount: 900, date: Date.new(2025, 12, 10))

      expect(suggestions).to eq([])
    end
  end

  describe "dated bill" do
    # THE WHOLE `detail`, AS ONE LITERAL — a hash rather than key-by-key assertions, so a member
    # that quietly appeared or vanished fails here rather than going unmentioned. Out of the example
    # only because it no longer fits on one line: `starts_holding` joined it in Task 5.
    def water_bill_detail
      {
        interval_months: 3,
        occurrences: 2,
        category_name: "Bills",
        starts_holding: true,
        last_seen_on: Date.new(2026, 1, 15),
        due_on: Date.new(2026, 4, 15),
        per_period_cost: 32.31
      }
    end

    it "proposes the highest observed amount on the median whole-month interval", :aggregate_failures do
      water = item("Water", in_category: category("Bills"))
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 210, on: Date.new(2026, 1, 15))

      suggestion = of_kind(:dated_bill).sole

      expect(suggestion.subject).to eq(water)
      expect(suggestion.amount).to eq(210)
      expect(suggestion.amount).to be_a(BigDecimal)
      expect(suggestion.detail).to eq(water_bill_detail)
    end

    # ** AN OPENING RECORD IS NOT HISTORY A DETECTOR MAY READ (fix round round 2 — item 5). ** Every
    # opening entry a user has hangs off ONE item, `Initial balance`, so two accounts corrected
    # downward a couple of months apart are two occurrences of one item at a regular gap — the exact
    # shape this detector fires on. It would have proposed a funding rule for `Opening Shortfall`, a
    # category the Budget page (narrowed by `Category.spendable`) does not even list. Excluded at
    # `SuggestionEngine#entry_rows`, the single read every lane composes from, so the fixture below
    # is the whole detector's population.
    it "does not fire on an account's opening records" do
      accounts = [create(:pool, :account, user: user, name: "Checking"), create(:pool, :account, user: user, name: "Ally")]
      shortfall = create(:category, :opening_shortfall, user: user)
      initial = item("Initial balance", in_category: shortfall)
      [[Date.new(2025, 11, 15), 200], [Date.new(2026, 1, 15), 210]].each_with_index do |(on, amount), index|
        create(:entry, item: initial, amount: amount, date: on, opening_account: accounts[index])
      end

      expect(of_kind(:dated_bill)).to be_empty
    end

    it "does not fire on an item that already carries a rule" do
      claimed = claimed_item("Water", category: funded_category("Water"), amount: 210, interval_months: 3, anchor_date: Date.new(2026, 4, 15))
      spend(claimed, 200, on: Date.new(2025, 10, 15))
      spend(claimed, 210, on: Date.new(2026, 1, 15))

      expect(of_kind(:dated_bill)).to be_empty
    end

    it "does not fire when the amounts are further than 25% apart" do
      water = item("Water", in_category: category("Bills"))
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 260, on: Date.new(2026, 1, 15))

      expect(of_kind(:dated_bill)).to be_empty
    end

    it "fires at exactly 25% apart" do
      water = item("Water", in_category: category("Bills"))
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 250, on: Date.new(2026, 1, 15))

      expect(of_kind(:dated_bill).sole.amount).to eq(250)
    end

    it "does not fire when the gap is not a whole number of months" do
      water = item("Water", in_category: category("Bills"))
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 200, on: Date.new(2025, 11, 30))

      expect(of_kind(:dated_bill)).to be_empty
    end

    it "tolerates a gap seven days off a whole month but not eight", :aggregate_failures do
      near = item("Near", in_category: category("Bills"))
      spend(near, 200, on: Date.new(2025, 11, 1))
      spend(near, 200, on: Date.new(2025, 12, 8))

      far = item("Far", in_category: category("Other bills"))
      spend(far, 300, on: Date.new(2025, 11, 1))
      spend(far, 300, on: Date.new(2025, 12, 9))

      expect(of_kind(:dated_bill).map(&:subject)).to eq([near])
    end

    # THE OCCURRENCE GATE (answers-first Home spec §7). A single payment used to be proposed as a
    # yearly bill with the guess admitted in the row itself; the shape is deleted, not demoted, so
    # the size that used to qualify it ($100, and $999 for good measure) buys nothing. The pair
    # below discriminates on the count alone: same item, same category, one payment then two.
    it "does not fire on a single occurrence, however large", :aggregate_failures do
      dentist = item("Dentist", in_category: category("Health bills"))
      spend(dentist, 999, on: Date.new(2025, 11, 20))

      expect(of_kind(:dated_bill)).to be_empty
      expect(suggestions.map(&:kind)).not_to include(:dated_bill)
    end

    it "fires as soon as the second occurrence lands", :aggregate_failures do
      dentist = item("Dentist", in_category: category("Health bills"))
      spend(dentist, 999, on: Date.new(2025, 11, 20))
      spend(dentist, 999, on: Date.new(2025, 12, 20))

      suggestion = of_kind(:dated_bill).sole

      expect(suggestion.amount).to eq(999)
      expect(suggestion.detail[:occurrences]).to eq(2)
      expect(suggestion.detail[:interval_months]).to eq(1)
      expect(suggestion.detail).not_to have_key(:guessed)
    end

    # The correction the demo measurement forced: verbatim this proposes a due date already in the
    # past, which BudgetCalculator reads as overdue the moment the rule is created.
    it "rolls the next due date forward past today rather than naming a date that has gone", :aggregate_failures do
      rent = item("Rent", in_category: category("Bills"))
      spend(rent, 900, on: Date.new(2025, 11, 1))
      spend(rent, 900, on: Date.new(2025, 12, 1))

      suggestion = of_kind(:dated_bill).sole

      expect(suggestion.detail[:last_seen_on]).to eq(Date.new(2025, 12, 1))
      expect(suggestion.detail[:due_on]).to eq(Date.new(2026, 3, 1))
    end

    # `Date#>>` clamps into a short month, and feeding the clamped date back in makes the clamp
    # permanent: Jan 31 → Feb 28 → Mar 28 → Apr 28, three days before the bill is actually paid.
    # Every candidate is `>>`-ed from the source instead, so the 31st survives February.
    it "keeps the day of the month when the roll passes through a short one", :aggregate_failures do
      rent = item("Rent", in_category: category("Bills"))
      spend(rent, 900, on: Date.new(2025, 12, 31))
      spend(rent, 900, on: Date.new(2026, 1, 31))

      suggestion = of_kind(:dated_bill, on: Date.new(2026, 4, 10)).sole

      expect(suggestion.detail[:interval_months]).to eq(1)
      expect(suggestion.detail[:due_on]).to eq(Date.new(2026, 4, 30))
      expect(suggestion.detail[:due_on]).not_to eq(Date.new(2026, 4, 28)) # the clamped-forward answer
    end

    # ONE HASH, WHERE THERE WERE TWO HALVES (two-ledger spec §3). The payload used to carry a `pool:`
    # to mint (name, type, account) plus a top-level `category_id` to be RE-POINTED at it, because
    # none of that was a `Budget` column. The owner IS a column now, so `category_id` travels inside
    # the budget half like any other field and there is no envelope half at all.
    # ** IT CARRIES THE FORM'S WORDS, NOT THE COLUMNS (rules-own-the-budget spec §4). ** `basis` is
    # no longer a permitted parameter of `BudgetsController::BUDGET_FIELDS`; `schedule` and `unspent`
    # are, and `RuleForm.from` is the one translator — so a payload spelled in columns here would be
    # a second copy of §2.1's table in a file whose subject is spending history, and would arrive at
    # the form as fields it drops on the floor.
    #
    # A DATED BILL PROPOSES `bill` (§3) AND `resets`. The type is what the give-way order is built
    # on, and the accept form shows the radio so the user confirms before anything is written;
    # `repeats` IS TRUE because the proposal names an interval: `by_date` + `repeats` is §2's row 4,
    # and the same pair with the box off is the one-off. There is no "unspent money" word on the wire
    # any more (two-shapes §7) — a dated rule's build-up has always been defined by its DATE.
    #
    # ** `keeps` RIDES AS `false` ON EVERY PROPOSAL (§12), AND IT IS THE CHECKBOX'S CONVENTION RATHER
    # THAN AN OPINION ABOUT THIS BILL. ** `RuleForm.from` reads back both boxes as booleans, so the
    # word is on the wire whichever way it points — `repeats: true` here is the same shape of answer.
    # No detector proposes a fund: a rule that keeps what it doesn't spend is a deliberate act about
    # money the household wants to accumulate, and there is nothing in spending history that measures
    # one.
    it "carries a prefill for the rule the proposal would create, owner included", :aggregate_failures do
      bills = category("Bills")
      water = item("Water", in_category: bills)
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 210, on: Date.new(2026, 1, 15))

      prefill = of_kind(:dated_bill).sole.prefill
      due = Date.new(2026, 4, 15)

      expect(prefill.keys).to eq([:budget])
      expect(prefill[:budget]).to eq(amount: 210, schedule: "by_date", repeats: true, keeps: false, interval_months: 3, anchor_date: due, item_id: water.id, category_id: bills.id, rule_type: "bill")
    end

    # TWO BILLS IN ONE CATEGORY ARE TWO RULES ON ONE OWNER, and that is now the ordinary case rather
    # than a design decision. It used to need arguing: `Budget#item_must_belong_to_pool` refused an
    # envelope named after the ITEM for every item-backed bill, and since a category pointed at one
    # pool, accepting one item-named proposal would have made its siblings unacceptable — 8 of the
    # demo's 10 bills. One category, one budget line; two rules, one category.
    it "gives two bills in one category the same owner, so both proposals can be accepted", :aggregate_failures do
      utilities = category("Utilities")
      two_dated_bills(utilities, amount: 60)

      halves = of_kind(:dated_bill).map { |suggestion| suggestion.prefill[:budget] }

      expect(halves.pluck(:category_id).uniq).to eq([utilities.id])
      expect(halves.pluck(:item_id).uniq.size).to eq(2)
    end

    # `starts_holding` IS THE WHOLE OF WHAT ACCEPTING CHANGES BESIDES THE RULE, so both directions
    # are pinned on one fixture: the same shape of bill in a category that holds nothing and in one
    # that already does. THREE EXAMPLES ARE DELETED INTO THIS ONE (two-ledger spec §5) — "reuses the
    # envelope a category already points at rather than proposing another", "offers a new envelope
    # when the category points at an account, which cannot carry a rule", and the rate detector's
    # "carries a prefill for an envelope, its rule and the category to attach" — each of which
    # pinned one branch of the reuse-or-mint cascade. Nothing is minted and nothing is reused; the
    # only thing left that differs between two proposing rows is this flag.
    it "says whether accepting would start the category holding money", :aggregate_failures do
      fresh = item("Water", in_category: category("Bills"))
      spend(fresh, 200, on: Date.new(2025, 11, 10))
      spend(fresh, 200, on: Date.new(2025, 12, 10))

      already = item("Gas", in_category: funded_category("Heat"))
      spend(already, 300, on: Date.new(2025, 11, 10))
      spend(already, 300, on: Date.new(2025, 12, 10))

      holding = of_kind(:dated_bill).to_h { |suggestion| [suggestion.subject, suggestion.detail[:starts_holding]] }

      expect(holding.fetch(fresh)).to be(true)
      expect(holding.fetch(already)).to be(false)
    end

    # Item 11: the panel leads with the claim that costs the most per period, not the largest
    # sticker. A $1,600 bill once a year is $61.54 a period; $1,500 every month is $692.31.
    it "ranks bills by what they cost a period, not by the size of the bill", :aggregate_failures do
      # TWO YEARS APART, because a yearly bill needs two occurrences to be one at all now
      # (#BILL_MIN_OCCURRENCES) and the older of them is still inside #HISTORY_YEARS. It used to
      # be a single payment wearing a guessed annual interval, which is the shape spec §7 deleted.
      annual = item("Tax bill", in_category: category("Tax"))
      spend(annual, 1_600, on: Date.new(2024, 11, 20))
      spend(annual, 1_600, on: Date.new(2025, 11, 20))
      rent = item("Rent", in_category: category("Home"))
      spend(rent, 1_500, on: Date.new(2025, 11, 20))
      spend(rent, 1_500, on: Date.new(2025, 12, 20))

      result = of_kind(:dated_bill)

      expect(result.map(&:amount)).to eq([1_500, 1_600])
      expect(result.map { |s| s.detail[:per_period_cost] }).to eq([692.31, 61.54])
      expect(result.map(&:subject)).to eq([rent, annual])
    end
  end

  describe "rate" do
    it "proposes the mean per-period spend of a category that holds nothing, seen in three of six periods", :aggregate_failures do
      coffee = category("Coffee")
      beans = item("Beans", in_category: coffee)
      in_last_three_periods(beans, [100, 120, 140])

      suggestion = of_kind(:rate).sole

      expect(suggestion.subject).to eq(coffee)
      expect(suggestion.amount).to eq(120)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { periods_present: 3, periods_measured: 3, periods_window: 6, observed_total: 360, first_seen_on: Date.new(2025, 12, 30), per_period_cost: 120, starts_holding: true }

      expect(suggestion.detail).to eq(expected)
    end

    it "does not fire on two of six periods" do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 100, on: Date.new(2026, 1, 12)) # P4
      spend(beans, 120, on: Date.new(2026, 1, 26)) # P5

      expect(of_kind(:rate)).to be_empty
    end

    # The second gate, and this task's own ruling: three appearances make it a flow, but a flow that
    # stopped three periods ago is not a claim on next period. Without it the divisor — which
    # anchors on FIRST appearance — proposes the dead flow as ongoing at half its old rate.
    it "does not fire on a flow that stopped before the last three periods", :aggregate_failures do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 300, on: Date.new(2025, 11, 20)) # P0
      spend(beans, 300, on: Date.new(2025, 12, 5)) # P1
      spend(beans, 300, on: Date.new(2025, 12, 18)) # P2

      expect(of_kind(:rate)).to be_empty
      expect(of_kind(:dated_bill)).to be_empty # and nothing else picked it up either
    end

    it "fires when the same three appearances reach into the last three periods" do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 300, on: Date.new(2025, 11, 20)) # P0
      spend(beans, 300, on: Date.new(2025, 12, 5)) # P1
      spend(beans, 300, on: Date.new(2025, 12, 30)) # P3 — the only difference

      expect(of_kind(:rate).sole.amount).to eq(150) # 900 over the six periods lived through
    end

    # THE POPULATION IS `funded_since IS NULL`, and this is its boundary. TWO EXAMPLES ARE DELETED
    # INTO IT (two-ledger spec §5): "fires on a category pointing at an account, which is the buffer
    # itself" and "starts firing on a category whose envelope was deleted" both existed to pin that
    # the pool era's two spellings of "nothing reserves this" — no pool, and an account — were one
    # set. There is one spelling now and this is it.
    it "does not fire on a category that already holds money, however regular the spending" do
      covered = funded_category("Groceries")
      in_last_three_periods(item("Food", in_category: covered), 100)

      expect(of_kind(:rate)).to be_empty
    end

    it "rounds the mean up to the nearest dollar" do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 100, on: Date.new(2025, 12, 30))
      spend(beans, 100, on: Date.new(2026, 1, 12))
      spend(beans, 150, on: Date.new(2026, 1, 26))

      expect(of_kind(:rate).sole.amount).to eq(117) # 350 / 3 = 116.66…
    end

    # The mixed-unit correction. Verbatim ("mean across the periods it APPEARED in") this category
    # is proposed at $300 a period — a per-OCCURRENCE figure wearing a per-period label — when the
    # money it actually needs every period is $150.
    it "divides by the periods lived through, not by the periods it appeared in", :aggregate_failures do
      # Amounts spread wider than the bill detector's 25% tolerance, so this is unambiguously a
      # flow rather than a dated bill on a two-monthly cycle.
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 200, on: Date.new(2025, 11, 20)) # P0
      spend(beans, 300, on: Date.new(2025, 12, 18)) # P2
      spend(beans, 400, on: Date.new(2026, 1, 15)) # P4

      suggestion = of_kind(:rate).sole

      expect(suggestion.amount).to eq(150) # 900 over six periods
      expect(suggestion.amount).not_to eq(300) # 900 over the three it appeared in
      expect(suggestion.detail[:periods_present]).to eq(3)
      expect(suggestion.detail[:periods_measured]).to eq(6)
    end

    # The other half of that correction: a category that only STARTED three periods ago is not
    # halved for the three periods before it existed.
    it "measures only from the first period the category appeared in" do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 300, on: Date.new(2025, 12, 30)) # P3
      spend(beans, 300, on: Date.new(2026, 1, 12)) # P4
      spend(beans, 300, on: Date.new(2026, 1, 26)) # P5

      expect(of_kind(:rate).sole.amount).to eq(300)
    end

    # A bill is not a rate. Verbatim, the rent below lands inside the category's "rate" average and
    # is proposed a second time, in a second unit, on the same screen.
    it "leaves out the spending it has already proposed as a dated bill", :aggregate_failures do
      home = category("Home")
      rent = item("Rent", in_category: home)
      [Date.new(2025, 11, 15), Date.new(2025, 12, 15), Date.new(2026, 1, 15)].each { |on| spend(rent, 900, on: on) }
      bits = item("Bits", in_category: home)
      in_last_three_periods(bits, 50)

      expect(of_kind(:dated_bill).sole.subject).to eq(rent)
      expect(of_kind(:rate).sole.amount).to eq(50)
      expect(of_kind(:rate).sole.amount).not_to eq(475) # 2,850 over six periods, rent included
    end

    # A RATE PROPOSES `usage` (§3): what this detector found is a category the user spends in every
    # period with no rule for it — a real need whose amount moves with how they live — and §2's row 1
    # is the allowance that resets with the paycheck. A fund names a DAY and is a deliberate act, not
    # something measured out of spending that already happened, which is why no detector proposes one.
    it "carries a prefill naming the category and the rate", :aggregate_failures do
      coffee = category("Coffee")
      beans = item("Beans", in_category: coffee)
      in_last_three_periods(beans, 120)

      expect(of_kind(:rate).sole.prefill).to eq(
        budget: {
          amount: 120, schedule: "per_period", repeats: false, keeps: false, category_id: coffee.id, rule_type: "usage"
        }
      )
    end
  end

  describe "drift" do
    # A category that holds money and carries a rate rule — a lane that can record spending. The
    # spending item lives IN that category, which is what the pool era arranged one layer out (a
    # second category pointing at the same pool).
    def rate_category(name, amount, **rule)
      category = funded_category(name)
      rule_record = create(:budget, :per_period_rate, category: category, amount: amount, **rule)
      [category, rule_record, item("#{name} food", in_category: category)]
    end

    # The same rule on a category that holds NOTHING: `ENTRY_CATEGORY_ID` sends its every entry to
    # available, so it records no spending by construction and its silence says nothing about the
    # user's behaviour.
    def unfunded_rule(name, amount)
      category = category(name)
      [category, create(:budget, :per_period_rate, category: category, amount: amount)]
    end

    # A USER WHO HAS BEEN HERE, in a category no drift fixture below touches. The gate (spec §7,
    # and the `describe "the history gate"` block that pins it both ways) is about the USER's
    # record, not the lane's, so the two fixtures that plant NO spending — the ones whose whole
    # point is a rule over a silent category — have to attach their rule to a user the engine has
    # a history for, or they would pass for the gate's reason rather than their own. P2, so the
    # count is four; one $20 entry proposes nothing itself.
    def history_of_their_own
      spend(item("Bus", in_category: category("Transit")), 20, on: Date.new(2025, 12, 20))
    end

    it "reports a rule the spending has outgrown", :aggregate_failures do
      _category, rule, food = rate_category("Groceries", 100)
      in_drift_window(food, 150)

      suggestion = of_kind(:drift).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.amount).to eq(150)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { rule_amount: 100, observed: 150, periods: 4, direction: :up, category_name: "Groceries", basis: "per_period", per_period_cost: 150 }

      expect(suggestion.detail).to eq(expected)
      expect(suggestion.prefill).to eq(id: rule.id, budget: { amount: 150 })
    end

    it "reports a rule the spending has fallen below", :aggregate_failures do
      _category, _, food = rate_category("Groceries", 200)
      in_drift_window(food, 100)

      suggestion = of_kind(:drift).sole

      expect(suggestion.amount).to eq(100)
      expect(suggestion.detail[:rule_amount]).to eq(200)
      expect(suggestion.detail[:direction]).to eq(:down)
    end

    it "does not fire at 9% away, however many dollars that is" do
      _category, _rule, food = rate_category("Groceries", 1_000)
      in_drift_window(food, 1_090)

      expect(of_kind(:drift)).to be_empty
    end

    it "does not fire under $10 away, however large the percentage" do
      _category, _rule, food = rate_category("Groceries", 50)
      in_drift_window(food, 55)

      expect(of_kind(:drift)).to be_empty
    end

    it "fires once both thresholds are past", :aggregate_failures do
      _category, _rule, food = rate_category("Groceries", 100)
      in_drift_window(food, 115)

      expect(of_kind(:drift).sole.amount).to eq(115)
      expect(of_kind(:drift).sole.detail[:rule_amount]).to eq(100)
    end

    # THE MIXED-UNIT PIN. $260 a month under a biweekly user is $120 a period, and the rule figure
    # reported has to be the normalised one — read off Budget#steady_ask, never off `amount`.
    it "states a monthly rate rule in per-period money", :aggregate_failures do
      utilities = funded_category("Utilities")
      rule = create(:budget, :rate, category: utilities, amount: 260)
      in_drift_window(item("Bills", in_category: utilities), 200)

      suggestion = of_kind(:drift).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.detail[:rule_amount]).to eq(120)
      expect(suggestion.detail[:rule_amount]).not_to eq(260)
      expect(suggestion.detail[:observed]).to eq(200)
      expect(suggestion.detail[:direction]).to eq(:up)
    end

    # ** THE PREFILL IS THE OBSERVED FIGURE, UNCONVERTED — AND THIS EXAMPLE IS THE INVERSE OF WHAT IT
    # WAS (two-shapes Task 4, fix round 1's ruling). ** It pinned `amount: 433.33`, the observed $200
    # a period multiplied back into the rule's MONTHLY column, because the rule form's box held that
    # column raw and writing $200 into it would have been $92.31 a period — less than the figure the
    # user had just been told was too low.
    #
    # The box does not hold that column. `RuleForm.from` reads a monthly-no-anchor row back as
    # per-period money, so the panel, the wire and the field are one unit and the inversion had
    # become the trap: $433.33 in a per-period box saves a rule asking 3.6× what the panel proposed.
    # `#rule_unit_amount` is deleted; the identity is the conversion.
    #
    # THE ROW'S OWN UNIT IS STILL REPORTED — `detail[:basis]` — because the drift sentence names it.
    it "puts the observed per-period figure on the wire, whatever the rule's own column", :aggregate_failures do
      utilities = funded_category("Utilities")
      rule = create(:budget, :rate, category: utilities, amount: 260)
      in_drift_window(item("Bills", in_category: utilities), 200)

      suggestion = of_kind(:drift).sole

      expect(suggestion.detail[:basis]).to eq("monthly")
      expect(suggestion.prefill).to eq(id: rule.id, budget: { amount: 200 })
      expect(suggestion.prefill[:budget][:amount]).not_to eq(433.33)
      # And the form it lands on is in that unit: the read-back divides the row to what it costs.
      expect(RuleForm.from(rule)).to include(schedule: "per_period", amount: 120.0)
    end

    it "leaves a per-period rule's prefill alone, because its column is already per-period", :aggregate_failures do
      _category, rule, food = rate_category("Groceries", 100)
      in_drift_window(food, 150)

      expect(of_kind(:drift).sole.detail[:basis]).to eq("per_period")
      expect(of_kind(:drift).sole.prefill).to eq(id: rule.id, budget: { amount: 150 })
    end

    # Amendment A subtracts item-backed items from the category's spend, so an item-backed RATE rule
    # would have its own lane subtracted from the figure meant to describe it.
    it "does not fire on an item-backed rate rule, whose own lane amendment A subtracts" do
      backed = claimed_item("Netflix", category: funded_category("Netflix"), amount: 20, basis: :per_period, interval_months: nil)
      in_drift_window(backed, 200)

      expect(of_kind(:drift)).to be_empty
    end

    it "fires on the same shape once the rule is item-less — the fixture discriminates", :aggregate_failures do
      netflix = funded_category("Netflix")
      rule = create(:budget, :per_period_rate, category: netflix, amount: 20)
      in_drift_window(item("Netflix", in_category: netflix), 200)

      expect(of_kind(:drift).sole.subject).to eq(rule)
      expect(of_kind(:drift).sole.amount).to eq(200)
    end

    it "does not fire on a dated rule, whose spending is not a rate" do
      insurance = funded_category("Car Insurance")
      create(:budget, :recurring, category: insurance, amount: 1_200, anchor_date: Date.new(2026, 6, 1))
      in_drift_window(item("Premium", in_category: insurance), 400)

      expect(of_kind(:drift)).to be_empty
    end

    # ** `SuggestionEngine#rate_shape?` READ `anchor_date`, `item_id` AND `cadence` AND NEVER THE
    # COLUMN THAT TOLD AN ACCRUING RULE FROM A USE-IT-OR-LOSE-IT RATE, so the detector described money
    # computed by a formula it does not know. ** `Budget#claim_shape` is the one door onto §3's
    # classification, and the accruing shape has been named three things — `:target` off the
    # CATEGORY's figure, `:building` off the rule's own carry-over column, and `:dated` since the two
    # shapes (§2). This method asks `== :rate` either way; the shape symbol is asserted BY NAME here
    # so a drift back to an old spelling fails in this file.
    #
    # PLANTED AT THE BACKWARDS SENTENCE: a $5,000 goal with $200 a period of spending. Read as a rate
    # rule the gap is past both thresholds and the panel says RAISE your contribution, which is
    # exactly wrong: the fund is being drained, not underfunded.
    it "does not fire on a goal, whose claim accrues toward a date", :aggregate_failures do
      vacation = funded_category("Vacation")
      rule = create(:budget, :by_date, category: vacation, amount: 5_000)
      in_drift_window(item("Flights", in_category: vacation), 200)

      expect(rule.claim_shape).to eq(:dated)
      expect(of_kind(:drift)).to be_empty
    end

    # ** AND NOT ON A FUND, WHICH IS THE SHAPE §12 BROUGHT BACK (two-shapes §12). ** It arrives with
    # a per-period cadence, an item-less lane and no anchor, so every clause of the pre-fix-wave
    # spelling would have admitted it — and drift's sentence is false about it twice. "You averaged
    # $200.00 a period, your rule says $50.00" is advice to stop a fund doing the one thing it exists
    # to do, and the two figures are not even about the same money: the detector compares a PERIOD's
    # spending against a rate, while a fund's claim is every period since it was written.
    #
    # THE SAME $50 RULE AND THE SAME $200 OF SPENDING AS THE EXAMPLE BELOW, one column apart, so the
    # pair is the gate rather than the fixture. The shape symbol is asserted by name for the reason
    # the goal example states.
    it "does not fire on a fund, which is meant to keep what it doesn't spend", :aggregate_failures do
      pet_care = funded_category("Pet Care")
      rule = create(:budget, :keeps_unspent, category: pet_care, amount: 50)
      in_drift_window(item("Kibble", in_category: pet_care), 200)

      expect(rule.claim_shape).to eq(:fund)
      expect(of_kind(:drift)).to be_empty
    end

    # ** THE "uncapped fund" AND "hand-fed $0 rule" EXAMPLES ARE DELETED WITH THEIR SHAPES (§7). **
    # The first was a rule that built up without naming a figure, planted to show the gate was the
    # SHAPE rather than the presence of a target; the second was the $0 rule `DropTheDistribution`
    # minted eight of, whose thresholds are both vacuous against zero. Neither can be written now: a
    # dated rule always names a figure and `Budget` validates `amount > 0` on every shape. The
    # `amount.positive?` gate is still exercised, on the row only a database can hold, below.

    # THE OTHER DIRECTION, one column apart: the same rule and the same spending on a rule whose
    # money RESETS is a rate rule, and it drifts. Without this the examples above would pass against
    # a detector that had simply stopped firing.
    it "fires on the same rule and the same spending once the rule's money resets", :aggregate_failures do
      _category, rule, food = rate_category("Vacation", 50)
      in_drift_window(food, 200)

      expect(rule.claim_shape).to eq(:rate)
      expect(of_kind(:drift).sole.subject).to eq(rule)
      expect(of_kind(:drift).sole.detail[:direction]).to eq(:up)
    end

    # ** THE `amount.positive?` GATE ON ITS OWN, ON A ROW ONLY A DATABASE CAN HOLD. ** A $0 rule
    # whose money RESETS is shape `:rate`, so the shape gate lets it through and only the amount gate
    # can silence it — and it must, because there is no rate there to have drifted from.
    #
    # WRITTEN PAST THE MODEL DELIBERATELY, and the bypass is the assertion: `Budget` validates
    # `amount > 0` on every shape since the two shapes (§2), so this row can no longer be SAVED at
    # all. It used to be one edit away — the target lived on the category and clearing it
    # re-validated nothing, so a user who retired a goal left exactly this row behind — and a
    # database restored from before `TwoShapes` can still be holding one.
    it "does not fire on a $0 rule whose money resets", :aggregate_failures do
      emergency = funded_category("Rainy Day")
      rule = create(:budget, :per_period_rate, category: emergency, amount: 25)
      in_drift_window(item("Repairs", in_category: emergency), 200)
      # rubocop:disable Rails/SkipsModelValidations -- the model refuses this row; a database does not
      rule.update_column(:amount, 0)
      # rubocop:enable Rails/SkipsModelValidations

      expect(rule.reload.claim_shape).to eq(:rate)
      expect(of_kind(:drift)).to be_empty
    end

    # AMENDMENT A. The bill payment below would take the average from $100 to $400 a period and
    # report drift on a rule that is exactly right.
    it "measures the rate rule's own lane, not the whole category's spend", :aggregate_failures do
      pet_care, _rule, food = rate_category("Pet Care", 100)
      in_drift_window(food, 100)
      bill = claimed_item("Vet", category: pet_care, amount: 1_200, interval_months: 12, anchor_date: Date.new(2026, 6, 1))
      spend(bill, 1_200, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift)).to be_empty
    end

    it "would have fired had the bill's item carried no rule of its own — the fixture discriminates" do
      pet_care, _rule, food = rate_category("Pet Care", 100)
      in_drift_window(food, 100)
      spend(item("Vet", in_category: pet_care), 1_200, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift).sole.amount).to eq(400)
    end

    # ** THE SHAPE IS NO LONGER WRITABLE, AND THE GUARD IS STILL LOAD-BEARING. **
    # `Budget#category_may_hold_one_item_less_rule` (computed-claims ruling of 2026-09-03) refuses a
    # second rule whose lane is the whole category, so this fixture is planted PAST the model. It is
    # not a shape this engine can stop meeting: rows written before that validation existed are in
    # real databases, and `#attributable_rate_rules` reads whatever rows are there. Giving the second
    # rule an ITEM instead would not preserve the example — `#rate_shape?` is item-less by
    # construction, so the category would be back to one attributable rate rule and drift would fire.
    it "is silent on a category carrying two rate rules, whose spend cannot be attributed" do
      groceries, _rule, food = rate_category("Groceries", 100)
      build(:budget, :per_period_rate, category: groceries, amount: 40).save(validate: false)
      in_drift_window(food, 300)

      expect(of_kind(:drift)).to be_empty
    end

    # The correction the demo forced, re-anchored: five of its envelopes had NO expense category
    # pointing at them, so verbatim they each reported "averaged $0.00 for 4 periods" — including a
    # $400 grocery rule the panel then asked the user to zero. The lane that cannot record is a
    # category that holds nothing now, and its $0.00 is a fact about the start-date rule.
    it "is silent on a rule whose category holds nothing, whose silence is not about spend" do
      history_of_their_own
      unfunded_rule("Groceries", 400)

      expect(of_kind(:drift)).to be_empty
    end

    # The lane that silence used to swallow. The two fixtures differ ONLY in whether the category
    # holds money; nothing is spent in either.
    it "reports $0.00 drift on a category that does hold money and nothing was spent out of", :aggregate_failures do
      history_of_their_own
      _category, rule, _food = rate_category("Groceries", 400)

      suggestion = of_kind(:drift).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.amount).to eq(0)
      expect(suggestion.amount).to be_a(BigDecimal)
      expect(suggestion.detail[:rule_amount]).to eq(400)
      expect(suggestion.detail[:observed]).to eq(0)
      expect(suggestion.detail[:direction]).to eq(:down)
      expect(suggestion.detail[:periods]).to eq(4)
    end

    it "fires on a single recorded entry too, so the figure moves with the evidence" do
      _category, _rule, food = rate_category("Groceries", 400)
      spend(food, 40, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift).sole.amount).to eq(10)
    end

    it "ignores spending in the current, incomplete period" do
      _category, _rule, food = rate_category("Groceries", 100)
      in_drift_window(food, 100)
      spend(food, 5_000, on: today)

      expect(of_kind(:drift)).to be_empty
    end
  end

  describe "dead rule" do
    def rule_with_history(amount:, last_seen_on:, **rule)
      backed = claimed_item("Netflix", category: funded_category("Netflix"), amount: amount, **rule)
      spend(backed, amount, on: last_seen_on)
      [backed.budget, backed]
    end

    it "reports an item-backed rule whose item stopped before the last three periods", :aggregate_failures do
      rule, backed = rule_with_history(amount: 75, last_seen_on: Date.new(2025, 11, 20), basis: :per_period, interval_months: nil)

      suggestion = of_kind(:dead_rule).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.amount).to eq(75)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { last_seen_on: Date.new(2025, 11, 20), periods_empty: 3, rule_amount: 75, item_name: backed.name, category_name: "Netflix", per_period_cost: 75 }

      expect(suggestion.detail).to eq(expected)
      expect(suggestion.prefill).to eq(id: rule.id)
    end

    it "states what a monthly dead rule costs a period, not what it says", :aggregate_failures do
      rule, = rule_with_history(amount: 260, last_seen_on: Date.new(2025, 11, 20), basis: :monthly, interval_months: 1)

      expect(of_kind(:dead_rule).sole.amount).to eq(120)
      expect(rule.amount).to eq(260)
    end

    it "does not fire when the item was still being spent two periods ago" do
      rule_with_history(amount: 75, last_seen_on: Date.new(2026, 1, 15), basis: :per_period, interval_months: nil)

      expect(of_kind(:dead_rule)).to be_empty
    end

    it "does not fire on the first day of the empty window" do
      rule_with_history(amount: 75, last_seen_on: Date.new(2025, 12, 26), basis: :per_period, interval_months: nil)

      expect(of_kind(:dead_rule)).to be_empty
    end

    it "fires on the day before it" do
      rule_with_history(amount: 75, last_seen_on: Date.new(2025, 12, 25), basis: :per_period, interval_months: nil)

      expect(of_kind(:dead_rule).sole.detail[:last_seen_on]).to eq(Date.new(2025, 12, 25))
    end

    it "does not fire on an item that never had an entry — that rule is new, not dead" do
      spend(item("Bus", in_category: category("Transit")), 20, on: Date.new(2025, 12, 20))
      claimed_item("Netflix", category: funded_category("Netflix"), amount: 75, basis: :per_period, interval_months: nil)

      expect(of_kind(:dead_rule)).to be_empty
    end

    it "does not fire on a rule with no item, which nothing can stop paying" do
      dentist = funded_category("Dentist")
      create(:budget, :per_period_rate, category: dentist, amount: 75)
      spend(item("Fillings", in_category: dentist), 75, on: Date.new(2025, 11, 20))

      expect(of_kind(:dead_rule)).to be_empty
    end

    # ** A FUND IS NEVER DEAD, AND SILENCE IS WHAT IT IS FOR (two-shapes §12). ** An item-backed fund
    # is a legal shape — a vet envelope on the Vet item that quietly builds until the day it is
    # needed — and this detector reads an item's silence as a rule that has stopped being used. For
    # a fund the silence is the point: the claim grew every period nothing was spent, and the money
    # is sitting there. "Consider deleting this rule" about a rule holding a year of savings is the
    # panel proposing to delete the household's savings.
    #
    # PAIRED WITH THE SAME HISTORY ON A RESETTING RULE, one column apart, so the gate is the SHAPE
    # and not the fixture.
    it "does not fire on an item-backed fund, whose silence is what it is for", :aggregate_failures do
      netflix = funded_category("Netflix")
      backed = create(:item, category: netflix, name: "Streaming")
      rule = create(:budget, :keeps_unspent, category: netflix, amount: 75, item: backed)
      spend(backed, 75, on: Date.new(2025, 11, 20))

      expect(rule.claim_shape).to eq(:fund)
      expect(of_kind(:dead_rule)).to be_empty
    end

    it "fires on the same item and the same history once the rule's money resets", :aggregate_failures do
      rule, = rule_with_history(amount: 75, last_seen_on: Date.new(2025, 11, 20), basis: :per_period, interval_months: nil)

      expect(rule.claim_shape).to eq(:rate)
      expect(of_kind(:dead_rule).sole.subject).to eq(rule)
    end
  end

  # THE HISTORY GATE (answers-first Home spec §7). Every window in this file is cut from
  # `#periods`, which is the CALENDAR's complete periods: the fixture user is anchored on today, so
  # six of them exist before a single entry does. Drift and dead-rule additionally require
  # #MIN_HISTORY_PERIODS complete periods of the USER's own, counted from the period their earliest
  # entry fell in — P4 opening on 2026-01-09 is two (P4 and P5), P5 opening on 2026-01-23 is one.
  #
  # The three examples are one fixture at three ages, so nothing but the date of the history entry
  # differs between the silence and the sentence.
  describe "the history gate" do
    # The drift shape the gate exists for: a category that HOLDS money, a rate rule on it, and no
    # spending in the window — which #drift_suggestion reports as the starkest drift there is
    # ("averaged $0.00 for 4 periods, your rule says $400"). Correct for a user with a record;
    # a claim about nothing for a user without one.
    def silent_rule
      groceries = funded_category("Groceries")
      create(:budget, :per_period_rate, category: groceries, amount: 400)
    end

    def history_on(date) = spend(item("Bus", in_category: category("Transit")), 20, on: date)

    # A DAY OLD, with both backward-looking shapes present in kind: a rule over a holder category,
    # and an item-backed rule. Today's spending is in the CURRENT period, which is in no window, so
    # the account's whole history is a period that has not closed.
    #
    # The drift half is what the gate removes — verbatim, before it, this fixture drew "$0.00 for 4
    # periods" on the user's first day. The dead-rule half is asserted because the ruling covers
    # both kinds, and it is honest about being over-determined: an item spent today is not silent,
    # so that detector would have said nothing here anyway.
    it "says nothing backward-looking to an account whose whole history is today", :aggregate_failures do
      silent_rule
      netflix = funded_category("Netflix")
      backed = claimed_item("Netflix", category: netflix, amount: 75, basis: :per_period, interval_months: nil)
      spend(backed, 75, on: today)
      spend(item("Food", in_category: funded_category("Dining")), 30, on: today)

      expect(of_kind(:drift)).to be_empty
      expect(of_kind(:dead_rule)).to be_empty
    end

    it "is still silent with one full period behind it" do
      silent_rule
      history_on(Date.new(2026, 1, 26))

      expect(of_kind(:drift)).to be_empty
    end

    it "speaks once a second full period has passed", :aggregate_failures do
      silent_rule
      history_on(Date.new(2026, 1, 12))

      suggestion = of_kind(:drift).sole

      expect(suggestion.amount).to eq(0)
      expect(suggestion.detail[:rule_amount]).to eq(400)
      expect(suggestion.detail[:periods]).to eq(4)
    end

    # THE ZERO-ENTRY PATH, WHICH IS NOT THE DAY-OLD PATH. Above, `history_start` is a real date and
    # the count is small; here there are no entries at all, so it is NIL and #periods_of_history
    # short-circuits to 0 rather than comparing a period edge against nothing. This is the state a
    # user is actually in the moment they finish onboarding — a period declared, an income figure,
    # rules written, and not one thing spent yet — and it reaches every detector, so the example
    # asserts the whole panel is empty and simply does not raise.
    it "says nothing at all to an account that has rules and income but has never spent", :aggregate_failures do
      user.update!(typical_income: 3_000)
      silent_rule
      claimed_item("Netflix", category: funded_category("Netflix"), amount: 75, basis: :per_period, interval_months: nil)

      expect { suggestions }.not_to raise_error
      expect(suggestions).to be_empty

      # And the fixture is not vacuous: the very same rules speak the moment a record exists.
      history_on(Date.new(2026, 1, 12))

      expect(of_kind(:drift)).not_to be_empty
    end
  end

  describe "order" do
    it "ranks by kind first, and the figures prove nothing else is deciding", :aggregate_failures do
      one_of_each

      result = suggestions

      expect(result.map(&:kind)).to eq([:dated_bill, :rate, :drift, :dead_rule])
      expect(result.map(&:amount)).to eq([120, 150, 200, 250])
      # The sort key, ascending in kind order too — so neither it nor `amount` could produce this
      # order on its own.
      expect(result.map { |suggestion| suggestion.detail[:per_period_cost] }).to eq([55.38, 150, 200, 250])
    end

    it "puts the larger amount first within a kind" do
      big = item("Big", in_category: category("Bills"))
      spend(big, 400, on: Date.new(2025, 11, 10))
      spend(big, 400, on: Date.new(2025, 12, 10))
      small = item("Small", in_category: category("Other bills"))
      spend(small, 120, on: Date.new(2025, 11, 10))
      spend(small, 120, on: Date.new(2025, 12, 10))

      expect(of_kind(:dated_bill).map(&:subject)).to eq([big, small])
    end

    it "breaks a tie on the subject's id", :aggregate_failures do
      first = item("First", in_category: category("Bills"))
      second = item("Second", in_category: category("Other bills"))
      [first, second].each do |backed|
        spend(backed, 300, on: Date.new(2025, 11, 10))
        spend(backed, 300, on: Date.new(2025, 12, 10))
      end

      result = of_kind(:dated_bill)

      expect(result.map(&:amount).uniq).to eq([300])
      expect(result.map { |suggestion| suggestion.subject.id }).to eq([first, second].map(&:id).sort)
    end
  end

  describe "the value object" do
    it "is a Data with the five members the panel renders" do
      expect(described_class::Suggestion.members).to eq([:kind, :subject, :amount, :detail, :prefill])
    end

    # `per_period_cost:` IS ON EVERY KIND because #ordered sorts on it and `fetch`es it. `guessed:`
    # was on every kind for the same reason — one member the panel could read without branching on
    # the kind — and it is on NONE now: the only shape that ever set it true is deleted (spec §7),
    # and a key that is a constant `false` on a money screen is a branch waiting to be believed.
    it "carries `per_period_cost:` on every kind, and `guessed:` on none of them", :aggregate_failures do
      one_of_each

      expect(suggestions.map { |suggestion| suggestion.detail.key?(:guessed) }).to eq([false, false, false, false])
      expect(suggestions.map { |suggestion| suggestion.detail[:per_period_cost] }).to all(be_a(BigDecimal))
    end
  end

  # ── ** THE PANEL MOVED INSIDE THE CATEGORY (two-shapes spec §4) ** ────────────────────────────
  #
  # `#by_category` partitions `#suggestions` and does nothing else: the Budget page's row badge
  # counts a bucket and its open panel renders one, so a suggestion in the wrong bucket is a row
  # proposing a rule for a category it is not about, and one in NO bucket is a suggestion the user
  # can never reach.
  describe "#by_category" do
    # ** THE PARTITION ITSELF, AS AN IDENTITY. ** Σ the buckets is the whole list and no suggestion
    # is in two of them — asserted over `one_of_each`, which is the only fixture in this file where
    # all four kinds fire at once and therefore the only one where all four `subject` classes (an
    # Item, a Category and two Budgets) are exercised together.
    it "partitions the suggestions exactly", :aggregate_failures do
      one_of_each
      buckets = engine.by_category

      expect(buckets.values.sum(&:size)).to eq(engine.suggestions.size)
      expect(buckets.values.flatten).to match_array(engine.suggestions)
    end

    # ** EACH KIND UNDER ITS OWN CATEGORY, and the three subject classes are three different
    # readings. ** A bill's category is its ITEM's, a rate's is the category it IS, and drift's and
    # a dead rule's are their RULE's — so a partition that asked one question of all four would put
    # three quarters of the panel in the wrong place, and `subject.id` (which every kind has) would
    # do it silently.
    it "files every kind under the category it is about", :aggregate_failures do
      one_of_each
      named = engine.by_category.transform_keys { |id| Category.find(id).name }

      expect(named["Bills"].map(&:kind)).to eq([:dated_bill])
      expect(named["Coffee"].map(&:kind)).to eq([:rate])
      expect(named["Groceries"].map(&:kind)).to eq([:drift])
      expect(named["Netflix"].map(&:kind)).to eq([:dead_rule])
    end

    # A CATEGORY WITH NOTHING IS ABSENT rather than mapped to an empty list, which is what lets the
    # row's badge be a `fetch` with a default and never a hash of empties to filter.
    it "leaves out a category with nothing to suggest" do
      one_of_each
      quiet = funded_category("Quiet")

      expect(engine.by_category).not_to have_key(quiet.id)
    end

    # ** A HIDDEN SUGGESTION IS OUT OF THE BUCKETS EXACTLY AS IT IS OUT OF THE PANEL, and it is in
    # `#hidden_by_category` instead. ** Both directions on one fixture: the same suggestion moves
    # from one partition to the other and the counts move with it, so a `#by_category` built off
    # `#detected` would fail the first half and a `#hidden_by_category` that dropped it the second.
    it "moves a hidden suggestion into the hidden partition", :aggregate_failures do
      one_of_each
      coffee = user.categories.find_by(name: "Coffee")
      user.suggestion_dismissals.create!(subject: coffee, kind: :rate)

      expect(engine.by_category).not_to have_key(coffee.id)
      expect(engine.hidden_by_category.fetch(coffee.id).map { |row| row.suggestion.kind }).to eq([:rate])
    end
  end

  # ** THE WINDOW FIGURE THE BUDGET PAGE'S RULE-LESS ROWS PRINT (two-shapes spec §4). ** `$X spent
  # in N periods`, and the whole point of it living here is that it is the SAME window the
  # suggestions beside it are measured in — a presenter cutting its own out of
  # `User#period_boundaries` could cut a different one and put two windows on one row.
  describe "#recent_spending" do
    # THE SIX COMPLETE PERIODS OF THE FILE HEADER, and the total is every entry in them. No
    # exclusions, unlike `#rates`' roll-up: this is "what left the account here", not "what left it
    # that is not already a proposed bill".
    it "totals a category's spending over the engine's own window", :aggregate_failures do
      beans = item("Beans", in_category: category("Coffee"))
      in_last_three_periods(beans, [150, 200, 250])
      coffee = user.categories.sole

      expect(engine.recent_spending.fetch(coffee.id).total).to eq(600)
      expect(engine.recent_spending.fetch(coffee.id).periods).to eq(6)
    end

    # THE CURRENT PERIOD IS IN NO WINDOW (see the file header), so a category spent in only today's
    # period is absent — which is the row saying "nothing spent yet", the honest sentence for a
    # measurement with nothing complete to measure.
    it "counts nothing from the period that has not closed" do
      beans = item("Beans", in_category: category("Coffee"))
      spend(beans, 150, on: today)

      expect(engine.recent_spending).to be_empty
    end

    # A USER WITH NO CADENCE HAS NO PERIODS, so there is no window to measure in — the same silence
    # every detector keeps, arriving on the row as the same sentence.
    it "is empty for a user who has declared no period" do
      stranger = create(:user, period_cadence: nil, period_anchor_date: nil)
      beans = create(:item, category: create(:category, :expense, user: stranger, name: "Coffee"))
      create(:entry, item: beans, amount: 150, date: today - 30)

      expect(engine(for_user: stranger).recent_spending).to be_empty
    end
  end

  describe "query cost" do
    def three_items
      ["One", "Two", "Three"].each_with_index do |name, index|
        backed = item(name, in_category: category("Bills #{index}"))
        spend(backed, 200 + index, on: Date.new(2025, 11, 10))
        spend(backed, 200 + index, on: Date.new(2025, 12, 10))
      end
    end

    def twelve_more
      (4..15).each do |index|
        backed = item("Item #{index}", in_category: category("Bills #{index}"))
        spend(backed, 300 + index, on: Date.new(2025, 11, 10))
        spend(backed, 300 + index, on: Date.new(2025, 12, 10))
      end
    end

    # A FRESH `User` FOR THE SECOND MEASUREMENT, and it is not tidiness. `#dismissals` reads
    # `user.suggestion_dismissals`, which the association caches on the record it was asked of — so
    # a second engine built over the SAME in-memory user answers that one for free, and the two
    # counts would differ by exactly that while nothing about the engine had changed. A request
    # always holds a freshly-loaded `current_user`, so this is the comparable pair.
    it "costs the same whether it proposes three bills or fifteen", :aggregate_failures do
      three_items
      small = query_count { suggestions }

      twelve_more
      fresh = User.find(user.id)
      large = query_count { engine(for_user: fresh).suggestions }

      expect(small).to eq(large)
      # categories, items, entries, rules, dismissals — no drift query, because no rule exists to
      # drift. ONE FEWER THAN THE POOL ERA'S SIX: `#expense_categories` dropped `includes(:pool)`
      # with the envelope half, and nothing here reads a pool any more. O(1) in bills either way,
      # which is what the first expectation pins.
      expect(large).to eq(5)
    end

    # The exact number, on a fixture that exercises every read the engine makes. `eq`, not `<=`: a
    # bound pins nothing, and the point of the figure is that the Budget page can be costed.
    #
    # NINE SINCE THE FIX WAVE, AND THE NINTH IS A PRELOAD (MED-2). `#rate_shape?` now asks
    # `Budget#claim_shape`, whose `ClaimCalculator` resolves `today` through `category.user`, so
    # `#budgets` preloads `category: :user` — the same nesting `Budget.steady_need` and
    # `ClaimLedger#rules` already carry. It is ONE `users` statement for the whole page against one
    # per category without it, which is the trade the figure records. It stays flat in rules: the
    # example above still measures three bills against fifteen and reads the same number.
    it "costs exactly nine queries when every detector has something to say", :aggregate_failures do
      one_of_each

      expect(query_count { suggestions }).to eq(9)
      expect(suggestions.size).to eq(4)
    end
  end
end
