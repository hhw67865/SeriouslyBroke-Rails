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
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  def engine(for_user: user, on: today) = described_class.new(user: for_user, today: on)

  def suggestions(...) = engine(...).suggestions

  def of_kind(kind, ...) = suggestions(...).select { |suggestion| suggestion.kind == kind }

  # `pool:` DEFAULTS TO THE ACCOUNT, not to nil. Every example here that leaves it out wants a
  # BUFFER-FUNDED category — the rate detector's population, and the shape whose proposals travel
  # down `#envelope_half`'s creation branch. That used to be spelled "no pool at all"; plan 3
  # requires a pool on every category, and an account IS the buffer (§7.1), so the account is the
  # same fixture in the vocabulary that survived. `Category#buffer_funded?` answers true for both.
  def category(name, pool: checking) = create(:category, :expense, user: user, name: name, pool: pool)

  def item(name, in_category:) = create(:item, category: in_category, name: name)

  def spend(on_item, amount, on:) = create(:entry, item: on_item, amount: amount, date: on)

  def envelope(name) = create(:pool, :budget_pool, user: user, account: checking, name: name)

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
  # that amendment A subtracts from a pool's drift spend.
  def claimed_item(name, pool:, amount: 500, **rule)
    owned = item(name, in_category: category("#{name} Spending", pool: pool))
    create(:pool_budget, pool: pool, item: owned, amount: amount, **rule)
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

    groceries = envelope("Groceries")
    create(:pool_budget, :per_period_rate, pool: groceries, amount: 100)
    in_drift_window(item("Food", in_category: category("Groceries Spending", pool: groceries)), 200)

    netflix = envelope("Netflix")
    backed = claimed_item("Netflix", pool: netflix, amount: 250, basis: :per_period, interval_months: nil)
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
    it "proposes the highest observed amount on the median whole-month interval", :aggregate_failures do
      water = item("Water", in_category: category("Bills"))
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 210, on: Date.new(2026, 1, 15))

      suggestion = of_kind(:dated_bill).sole

      expect(suggestion.subject).to eq(water)
      expect(suggestion.amount).to eq(210)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { interval_months: 3, occurrences: 2, guessed: false, category_name: "Bills", last_seen_on: Date.new(2026, 1, 15), due_on: Date.new(2026, 4, 15), per_period_cost: 32.31 }

      expect(suggestion.detail).to eq(expected)
    end

    it "does not fire on an item that already carries a rule" do
      pool = envelope("Water")
      claimed = claimed_item("Water", pool: pool, amount: 210, interval_months: 3, anchor_date: Date.new(2026, 4, 15))
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

    it "guesses a yearly interval for a single occurrence of $100 or more", :aggregate_failures do
      dentist = item("Dentist", in_category: category("Health bills"))
      spend(dentist, 100, on: Date.new(2025, 11, 20))

      suggestion = of_kind(:dated_bill).sole

      expect(suggestion.amount).to eq(100)
      expect(suggestion.detail[:interval_months]).to eq(12)
      expect(suggestion.detail[:occurrences]).to eq(1)
      expect(suggestion.detail[:guessed]).to be(true)
      expect(suggestion.detail[:due_on]).to eq(Date.new(2026, 11, 20))
    end

    it "does not guess for a single occurrence under $100" do
      dentist = item("Dentist", in_category: category("Health bills"))
      spend(dentist, 99.99, on: Date.new(2025, 11, 20))

      expect(of_kind(:dated_bill)).to be_empty
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

    it "carries a prefill for the pool and the rule the proposal would create", :aggregate_failures do
      user.update!(default_account: checking)
      bills = category("Bills")
      water = item("Water", in_category: bills)
      spend(water, 200, on: Date.new(2025, 10, 15))
      spend(water, 210, on: Date.new(2026, 1, 15))

      prefill = of_kind(:dated_bill).sole.prefill

      expect(prefill[:pool]).to eq(name: "Bills", pool_type: "budget", account_id: checking.id)
      expect(prefill[:category_id]).to eq(bills.id)
      expect(prefill[:budget]).to eq(amount: 210, basis: "monthly", interval_months: 3, anchor_date: Date.new(2026, 4, 15), item_id: water.id)
    end

    # THE ENVELOPE IS THE CATEGORY'S. An envelope named after the ITEM is refused by
    # `Budget#item_must_belong_to_pool` for every bill, and — since a category points at one pool —
    # accepting one item-named proposal would make its siblings unacceptable.
    it "gives two bills in one category the same envelope, so both proposals can be accepted", :aggregate_failures do
      utilities = category("Utilities")
      ["Phone", "Internet"].each_with_index do |name, index|
        bill = item(name, in_category: utilities)
        spend(bill, 60 + index, on: Date.new(2025, 11, 20))
        spend(bill, 60 + index, on: Date.new(2025, 12, 20))
      end

      halves = of_kind(:dated_bill).map { |suggestion| suggestion.prefill.except(:budget) }

      expect(halves.uniq.size).to eq(1)
      expect(halves.first).to eq(pool: { name: "Utilities", pool_type: "budget", account_id: nil }, category_id: utilities.id)
      expect(of_kind(:dated_bill).map { |s| s.prefill[:budget][:item_id] }.uniq.size).to eq(2)
    end

    it "reuses the envelope a category already points at rather than proposing another", :aggregate_failures do
      pool = envelope("Utilities")
      bill = item("Phone", in_category: category("Utility Bills", pool: pool))
      spend(bill, 60, on: Date.new(2025, 11, 20))
      spend(bill, 60, on: Date.new(2025, 12, 20))

      prefill = of_kind(:dated_bill).sole.prefill

      expect(prefill[:pool_id]).to eq(pool.id)
      expect(prefill).not_to have_key(:pool)
      expect(prefill).not_to have_key(:category_id)
    end

    # An ACCOUNT is not reusable — `Budget#pool_must_not_be_an_account` refuses a rule on one — so a
    # category pointing at an account gets the same new-envelope offer an unpooled one does. The
    # demo's "Estimated Taxes" category is exactly this shape.
    it "offers a new envelope when the category points at an account, which cannot carry a rule", :aggregate_failures do
      taxes = category("Estimated Taxes", pool: checking)
      bill = item("Federal Estimate", in_category: taxes)
      spend(bill, 1_600, on: Date.new(2025, 11, 20))

      prefill = of_kind(:dated_bill).sole.prefill

      expect(prefill).not_to have_key(:pool_id)
      expect(prefill[:pool]).to eq(name: "Estimated Taxes", pool_type: "budget", account_id: nil)
      expect(prefill[:category_id]).to eq(taxes.id)
    end

    # Item 11: the panel leads with the claim that costs the most per period, not the largest
    # sticker. A $1,600 bill once a year is $61.54 a period; $1,500 every month is $692.31.
    it "ranks bills by what they cost a period, not by the size of the bill", :aggregate_failures do
      annual = item("Tax bill", in_category: category("Tax"))
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
    it "proposes the mean per-period spend of a budgetable category seen in three of six periods", :aggregate_failures do
      coffee = category("Coffee")
      beans = item("Beans", in_category: coffee)
      in_last_three_periods(beans, [100, 120, 140])

      suggestion = of_kind(:rate).sole

      expect(suggestion.subject).to eq(coffee)
      expect(suggestion.amount).to eq(120)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { periods_present: 3, periods_measured: 3, periods_window: 6, observed_total: 360, first_seen_on: Date.new(2025, 12, 30), per_period_cost: 120, guessed: false }

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

    it "does not fire on a category a pool already covers, however regular the spending" do
      covered = category("Groceries Spending", pool: envelope("Groceries"))
      food = item("Food", in_category: covered)
      in_last_three_periods(food, 100)

      expect(of_kind(:rate)).to be_empty
    end

    # THE OTHER HALF OF THAT SENTENCE — Task 8's fix round. An ACCOUNT is the buffer, so a category
    # pointing at one is buffer-funded exactly as an un-pooled one is, and the detector's sentence
    # ("this comes out of your buffer") is literally true of it. The population became reachable in
    # bulk when destroying an envelope started re-pointing its categories to the account instead of
    # nullifying them: without this the app would go permanently silent about spending it had just
    # handed back to the buffer.
    it "fires on a category pointing at an account, which is the buffer itself", :aggregate_failures do
      user.update!(default_account: checking)
      buffered = category("Coffee", pool: checking)
      in_last_three_periods(item("Beans", in_category: buffered), 120)

      suggestion = of_kind(:rate).sole

      expect(suggestion.subject).to eq(buffered)
      expect(suggestion.amount).to eq(120)
      # The CREATION branch, not reuse: an account is not an envelope, so accepting makes one and
      # re-points the category into it.
      expect(suggestion.prefill[:pool]).to eq(name: "Coffee", pool_type: "budget", account_id: checking.id)
      expect(suggestion.prefill[:category_id]).to eq(buffered.id)
      expect(suggestion.prefill).not_to have_key(:pool_id)
    end

    # An envelope that was deleted is the path that produces the shape above, end to end.
    it "starts firing on a category whose envelope was deleted", :aggregate_failures do
      groceries = envelope("Groceries")
      covered = category("Groceries Spending", pool: groceries)
      in_last_three_periods(item("Food", in_category: covered), 100)

      expect(of_kind(:rate)).to be_empty

      groceries.destroy

      expect(covered.reload.pool).to eq(checking)
      expect(of_kind(:rate).sole.subject).to eq(covered)
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

    it "carries a prefill for an envelope, its rule and the category to attach", :aggregate_failures do
      user.update!(default_account: checking)
      coffee = category("Coffee")
      beans = item("Beans", in_category: coffee)
      in_last_three_periods(beans, 120)

      prefill = of_kind(:rate).sole.prefill

      expect(prefill[:pool]).to eq(name: "Coffee", pool_type: "budget", account_id: checking.id)
      expect(prefill[:budget]).to eq(amount: 120, basis: "per_period")
      expect(prefill[:category_id]).to eq(coffee.id)
    end
  end

  describe "drift" do
    # An envelope with a rate rule AND a category pointing at it — a lane that can record spending.
    def rate_envelope(name, amount, **rule)
      pool = envelope(name)
      rule_record = create(:pool_budget, :per_period_rate, pool: pool, amount: amount, **rule)
      food = item("#{name} food", in_category: category("#{name} Spending", pool: pool))
      [pool, rule_record, food]
    end

    # The same envelope with NO category pointing at it: it cannot record spending, so its silence
    # says nothing about the user's behaviour.
    def unfed_envelope(name, amount)
      pool = envelope(name)
      [pool, create(:pool_budget, :per_period_rate, pool: pool, amount: amount)]
    end

    it "reports a rule the spending has outgrown", :aggregate_failures do
      _pool, rule, food = rate_envelope("Groceries", 100)
      in_drift_window(food, 150)

      suggestion = of_kind(:drift).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.amount).to eq(150)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { rule_amount: 100, observed: 150, periods: 4, direction: :up, pool_name: "Groceries", basis: "per_period", per_period_cost: 150, guessed: false }

      expect(suggestion.detail).to eq(expected)
      expect(suggestion.prefill).to eq(id: rule.id, budget: { amount: 150 })
    end

    it "reports a rule the spending has fallen below", :aggregate_failures do
      _pool, _, food = rate_envelope("Groceries", 200)
      in_drift_window(food, 100)

      suggestion = of_kind(:drift).sole

      expect(suggestion.amount).to eq(100)
      expect(suggestion.detail[:rule_amount]).to eq(200)
      expect(suggestion.detail[:direction]).to eq(:down)
    end

    it "does not fire at 9% away, however many dollars that is" do
      _pool, _rule, food = rate_envelope("Groceries", 1_000)
      in_drift_window(food, 1_090)

      expect(of_kind(:drift)).to be_empty
    end

    it "does not fire under $10 away, however large the percentage" do
      _pool, _rule, food = rate_envelope("Groceries", 50)
      in_drift_window(food, 55)

      expect(of_kind(:drift)).to be_empty
    end

    it "fires once both thresholds are past", :aggregate_failures do
      _pool, _rule, food = rate_envelope("Groceries", 100)
      in_drift_window(food, 115)

      expect(of_kind(:drift).sole.amount).to eq(115)
      expect(of_kind(:drift).sole.detail[:rule_amount]).to eq(100)
    end

    # THE MIXED-UNIT PIN. $260 a month under a biweekly user is $120 a period, and the rule figure
    # reported has to be the normalised one — read off Budget#steady_ask, never off `amount`.
    it "states a monthly rate rule in per-period money", :aggregate_failures do
      pool = envelope("Utilities")
      rule = create(:pool_budget, :rate, pool: pool, amount: 260)
      food = item("Bills", in_category: category("Utility Spending", pool: pool))
      in_drift_window(food, 200)

      suggestion = of_kind(:drift).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.detail[:rule_amount]).to eq(120)
      expect(suggestion.detail[:rule_amount]).not_to eq(260)
      expect(suggestion.detail[:observed]).to eq(200)
      expect(suggestion.detail[:direction]).to eq(:up)
    end

    # THE SAME TRAP IN THE HALF THAT WRITES. Everything the panel reports is per-period; the column
    # the form writes into is MONTHLY on this shape. `amount: 200` there is $92.31 a period — LESS
    # than the $120 the user was just told was too low, on a suggestion that asked them to raise it.
    it "puts the drift prefill in the rule's own unit, not in per-period money", :aggregate_failures do
      pool = envelope("Utilities")
      rule = create(:pool_budget, :rate, pool: pool, amount: 260)
      food = item("Bills", in_category: category("Utility Spending", pool: pool))
      in_drift_window(food, 200)

      suggestion = of_kind(:drift).sole

      expect(suggestion.detail[:basis]).to eq("monthly")
      expect(suggestion.prefill).to eq(id: rule.id, budget: { amount: 433.33 })
      expect(suggestion.prefill[:budget][:amount]).not_to eq(200)
      # And the round trip through the app's own normaliser lands back on the observed figure.
      expect(Budget.new(amount: 433.33, basis: :monthly, interval_months: 1).steady_ask(user, today: today)).to eq(200)
    end

    it "leaves a per-period rule's prefill alone, because its column is already per-period", :aggregate_failures do
      _pool, rule, food = rate_envelope("Groceries", 100)
      in_drift_window(food, 150)

      expect(of_kind(:drift).sole.detail[:basis]).to eq("per_period")
      expect(of_kind(:drift).sole.prefill).to eq(id: rule.id, budget: { amount: 150 })
    end

    # Amendment A subtracts item-backed items from the pool's spend, so an item-backed RATE rule
    # would have its own lane subtracted from the figure meant to describe it.
    it "does not fire on an item-backed rate rule, whose own lane amendment A subtracts" do
      pool = envelope("Netflix")
      backed = claimed_item("Netflix", pool: pool, amount: 20, basis: :per_period, interval_months: nil)
      in_drift_window(backed, 200)

      expect(of_kind(:drift)).to be_empty
    end

    it "fires on the same shape once the rule is item-less — the fixture discriminates", :aggregate_failures do
      pool = envelope("Netflix")
      rule = create(:pool_budget, :per_period_rate, pool: pool, amount: 20)
      food = item("Netflix", in_category: category("Netflix Spending", pool: pool))
      in_drift_window(food, 200)

      expect(of_kind(:drift).sole.subject).to eq(rule)
      expect(of_kind(:drift).sole.amount).to eq(200)
    end

    it "does not fire on a dated rule, whose spending is not a rate" do
      pool = envelope("Car Insurance")
      create(:pool_budget, :recurring, pool: pool, amount: 1_200, anchor_date: Date.new(2026, 6, 1))
      food = item("Premium", in_category: category("Insurance Spending", pool: pool))
      in_drift_window(food, 400)

      expect(of_kind(:drift)).to be_empty
    end

    # AMENDMENT A. The bill payment below would take the average from $100 to $400 a period and
    # report drift on a rule that is exactly right.
    it "measures the rate rule's own lane, not the whole pool's spend", :aggregate_failures do
      pool, _rule, food = rate_envelope("Pet Care", 100)
      in_drift_window(food, 100)
      bill = claimed_item("Vet", pool: pool, amount: 1_200, interval_months: 12, anchor_date: Date.new(2026, 6, 1))
      spend(bill, 1_200, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift)).to be_empty
    end

    it "would have fired had the bill's item carried no rule of its own — the fixture discriminates" do
      pool, _rule, food = rate_envelope("Pet Care", 100)
      in_drift_window(food, 100)
      unclaimed = item("Vet", in_category: category("Vet Spending", pool: pool))
      spend(unclaimed, 1_200, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift).sole.amount).to eq(400)
    end

    it "is silent on a pool carrying two rate rules, whose spend cannot be attributed" do
      pool, _rule, food = rate_envelope("Groceries", 100)
      create(:pool_budget, :per_period_rate, pool: pool, amount: 40)
      in_drift_window(food, 300)

      expect(of_kind(:drift)).to be_empty
    end

    # The correction the demo forced: five of its envelopes have NO expense category pointing at
    # them, so verbatim they each reported "averaged $0.00 for 4 periods" — including a $400
    # grocery rule the panel then asked the user to zero.
    it "is silent on a pool no category feeds, whose silence is about tracking and not about spend" do
      unfed_envelope("Groceries", 400)

      expect(of_kind(:drift)).to be_empty
    end

    # The lane that silence used to swallow. The two fixtures differ ONLY in whether a category
    # points at the pool; nothing is spent in either.
    it "reports $0.00 drift on a pool a category does feed and nothing was spent out of", :aggregate_failures do
      _pool, rule, _food = rate_envelope("Groceries", 400)

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
      _pool, _rule, food = rate_envelope("Groceries", 400)
      spend(food, 40, on: Date.new(2026, 1, 15))

      expect(of_kind(:drift).sole.amount).to eq(10)
    end

    it "ignores spending in the current, incomplete period" do
      _pool, _rule, food = rate_envelope("Groceries", 100)
      in_drift_window(food, 100)
      spend(food, 5_000, on: today)

      expect(of_kind(:drift)).to be_empty
    end
  end

  describe "dead rule" do
    def rule_with_history(amount:, last_seen_on:, **rule)
      pool = envelope("Netflix")
      backed = claimed_item("Netflix", pool: pool, amount: amount, **rule)
      spend(backed, amount, on: last_seen_on)
      [backed.budget, backed]
    end

    it "reports an item-backed rule whose item stopped before the last three periods", :aggregate_failures do
      rule, backed = rule_with_history(amount: 75, last_seen_on: Date.new(2025, 11, 20), basis: :per_period, interval_months: nil)

      suggestion = of_kind(:dead_rule).sole

      expect(suggestion.subject).to eq(rule)
      expect(suggestion.amount).to eq(75)
      expect(suggestion.amount).to be_a(BigDecimal)
      expected = { last_seen_on: Date.new(2025, 11, 20), periods_empty: 3, rule_amount: 75, item_name: backed.name, pool_name: "Netflix", per_period_cost: 75, guessed: false }

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
      pool = envelope("Netflix")
      claimed_item("Netflix", pool: pool, amount: 75, basis: :per_period, interval_months: nil)

      expect(of_kind(:dead_rule)).to be_empty
    end

    it "does not fire on a rule with no item, which nothing can stop paying" do
      pool = envelope("Dentist")
      create(:pool_budget, :per_period_rate, pool: pool, amount: 75)
      food = item("Fillings", in_category: category("Dentist Spending", pool: pool))
      spend(food, 75, on: Date.new(2025, 11, 20))

      expect(of_kind(:dead_rule)).to be_empty
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
    it "is a Data with the five members Task 7 renders" do
      expect(described_class::Suggestion.members).to eq([:kind, :subject, :amount, :detail, :prefill])
    end

    it "carries `guessed:` and `per_period_cost:` on every kind, not only on the kinds that need them", :aggregate_failures do
      one_of_each

      expect(suggestions.map { |suggestion| suggestion.detail.key?(:guessed) }).to eq([true, true, true, true])
      expect(suggestions.map { |suggestion| suggestion.detail[:per_period_cost] }).to all(be_a(BigDecimal))
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

    it "costs the same whether it proposes three bills or fifteen", :aggregate_failures do
      three_items
      small = query_count { suggestions }

      twelve_more
      large = query_count { engine.suggestions }

      expect(small).to eq(large)
      # categories, their pools, items, entries, rules — no drift query, because no rule exists to
      # drift. The pool preload was FREE before plan 3 (`includes(:pool)` skips its query when every
      # `pool_id` is nil, and a category could name no pool); every category names one now, so the
      # figure is five. O(1) in bills either way, which is what the first expectation pins.
      expect(large).to eq(5)
    end

    # The exact number, on a fixture that exercises every read the engine makes. `eq`, not `<=`: a
    # bound pins nothing, and the point of the figure is that the Budget page can be costed.
    it "costs exactly eight queries when every detector has something to say", :aggregate_failures do
      one_of_each

      expect(query_count { suggestions }).to eq(8)
      expect(suggestions.size).to eq(4)
    end
  end
end
