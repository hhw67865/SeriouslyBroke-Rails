# frozen_string_literal: true

require "rails_helper"

# EVERY CLAIM A USER HAS, AND WHAT IS LEFT OVER (computed-claims spec §2).
#
# EVERY FIGURE IS A PLANTED LITERAL, on `category_ledger_spec`'s rule: `free == total_money −
# total_claims` asserted against the ledger's own terms is `x == x` and would pass against a class
# summing the wrong column. `free` is asserted against the money the fixture actually put there —
# $3,000 earned, $1,000 moved to savings, $250 spent — and the claims against the periods walked.
#
# ** THE ONE-SPELLING GROUP IS THE POINT OF THIS FILE. ** A batched ledger and an unbatched
# calculator are two readers of one rule, and the failure mode is not a crash: it is a Home screen
# quietly reporting a different number than the category page beside it. So the batched figure is
# asserted EQUAL to the per-rule one, rule by rule, on a fixture that exercises both spending lanes
# and both directions of the adjustment sign.
RSpec.describe ClaimLedger, type: :model do
  # A RULE ACCRUES FROM THE LATER OF ITS CATEGORY'S FUNDING DATE AND ITS OWN CREATION (§3.2), so a
  # fixture whose fund has been building since January has to say the rule existed in January.
  def born = Time.utc(2026, 1, 1, 9, 0)

  let(:user) { create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1)) }
  let(:today) { Date.new(2026, 9, 3) } # the period is Sep 1 – Sep 30
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:groceries) { create(:category, :expense, user: user, name: "Groceries", funded_since: Date.new(2026, 1, 1)) }
  let(:vacation) do
    create(
      :category,
      :expense,
      user: user,
      name: "Vacation",
      funded_since: Date.new(2026, 1, 1),
      target_amount: 1_200
    )
  end
  let(:groceries_rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }
  let(:vacation_rule) { create(:budget, :per_period_rate, category: vacation, amount: 150, created_at: born) }
  let(:ledger) { described_class.new(user, today: today) }

  # $3,000 in on Jan 5, $1,000 of it moved to Ally, $250 of groceries on Sep 2.
  #   pot          = 3000 − 250 − 1000 = 1750
  #   total_money  = 1750 + 1000       = 2750
  #   Groceries    = 400 − 250         =  150
  #   Vacation     = 9 periods × 150, capped at the category's 1,200
  #   Σ claims     = 1350
  before do
    create(:pool, :account, user: user, name: "Checking")
    earn(3_000, on: Date.new(2026, 1, 5))
    create(
      :account_movement,
      from_pool: user.default_account,
      to_pool: ally,
      amount: 1_000,
      date: Time.utc(2026, 1, 6, 12)
    )
    spend(groceries, 250, on: Date.new(2026, 9, 2))
    groceries_rule
    vacation_rule
  end

  def earn(amount, on:)
    category = user.categories.incomes.first || create(:category, :income, user: user, name: "Pay")
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def spend(category, amount, on:, item: nil)
    create(:entry, item: item || create(:item, category: category), amount: amount, date: on)
  end

  describe "#claim_of and #total_claims" do
    it "answers each rule's claim and their sum", :aggregate_failures do
      expect(ledger.claim_of(groceries_rule)).to eq(150)
      expect(ledger.claim_of(vacation_rule)).to eq(1_200)
      expect(ledger.total_claims).to eq(1_350)
    end

    it "claims nothing at all for a user with no rules" do
      stranger = create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))

      expect(described_class.new(stranger, today: today).total_claims).to eq(0)
    end

    # A RULE THIS LEDGER WAS NEVER BUILT OVER WAS NOT ASKED ABOUT, which is a different fact from
    # claiming nothing — `CategoryLedger#holding_of`'s rule, and its shape.
    it "refuses a rule belonging to somebody else" do
      theirs = create(:budget, :per_period_rate, amount: 99)

      expect { ledger.claim_of(theirs) }.to raise_error(described_class::UnknownRule)
    end
  end

  # ** ONE SPELLING: the batched figure and the per-rule one, on the same rows. ** Four rules across
  # both lanes, a dated bill among them, an adjustment of each sign.
  describe "against the per-rule calculator" do
    it "answers exactly what each rule's own calculator answers", :aggregate_failures do
      rules = mixed_rules

      rules.each do |rule|
        expect(ledger.claim_of(rule)).to eq(rule.claim_calculator(today: today).claim)
      end
    end

    it "agrees about the walk itself and not merely about its total", :aggregate_failures do
      premium = mixed_rules.last
      batched = ledger.calculator_for(premium)
      alone = premium.claim_calculator(today: today)

      expect(batched.built_up).to eq(alone.built_up)
      expect(batched.next_due_on).to eq(alone.next_due_on)
      expect(batched.spent_this_period).to eq(alone.spent_this_period)
    end

    # Groceries (category lane, $250 spent this period, −$100 delta), Vacation (a +$500 set-aside),
    # and a $600 six-monthly premium on its own item, half paid.
    def mixed_rules
      create(:adjustment, rule: groceries_rule, amount: -100, date: Time.utc(2026, 9, 2, 12))
      create(:adjustment, rule: vacation_rule, amount: 500, date: Time.utc(2026, 3, 10, 12))
      item = create(:item, category: groceries, name: "Premium")
      premium = create(
        :budget,
        category: groceries,
        item: item,
        amount: 600,
        interval_months: 6,
        anchor_date: Date.new(2026, 6, 1),
        created_at: born
      )
      spend(groceries, 300, on: Date.new(2026, 6, 5), item: item)
      [groceries_rule, vacation_rule, premium]
    end
  end

  describe "#free" do
    # 2,750 − 1,350 = 1,400, which is less than the 1,750 the pot holds — so the claims bind.
    it "is the total money less every claim", :aggregate_failures do
      expect(ledger.total_money).to eq(2_750)
      expect(ledger.free).to eq(1_400)
      expect(ledger).not_to be_free_cap_bound
    end

    # ** THE CAP (§2/§3 of the answers-first spec): money in a savings account is not free to spend
    # out of checking. ** Another $1,000 moved to Ally leaves the same $1,400 unclaimed and only $750
    # in the pot, and `free` follows the pot.
    it "never promises more than the pot holds", :aggregate_failures do
      create(
        :account_movement,
        from_pool: user.default_account,
        to_pool: ally,
        amount: 1_000,
        date: Time.utc(2026, 1, 7, 12)
      )

      expect(ledger.free).to eq(750)
      expect(ledger).to be_free_cap_bound
    end

    # ** BELOW ZERO IS A SIGNAL, NEVER A REFUSAL (§4). ** A $5,000 bill due Oct 1 on a category funded
    # this month claims half of itself now — two periods to fill it, this one and the Oct one — and
    # the user is $1,100 short.
    it "goes negative rather than clamping when the claims outrun the money", :aggregate_failures do
      car = create(:category, :expense, user: user, name: "Car", funded_since: Date.new(2026, 9, 1))
      create(:budget, category: car, amount: 5_000, interval_months: nil, anchor_date: Date.new(2026, 10, 1), created_at: Time.utc(2026, 9, 1, 9, 0))

      expect(ledger.total_claims).to eq(3_850)
      expect(ledger.free).to eq(-1_100)
    end
  end

  # ** THREE STATEMENTS FOR A WHOLE USER, HOWEVER MANY RULES THERE ARE (the plan's interface). **
  # Counted per TABLE rather than as a total, because the rule load and its preloads are not what this
  # pins: what is pinned is that the two spending lanes and the delta table are read ONCE each, since
  # the per-rule path this class replaces costs one entry query and one adjustment query per rule.
  #
  # MEASURED IN BOTH DIRECTIONS on this exact fixture — eight rules across both lanes:
  #
  #   batched (this class)          — 2 entry statements, 1 adjustment statement
  #   eight unbatched calculators   — 8 entry statements, 8 adjustment statements (21 in total)
  #
  # so the counts below are O(1) against O(n) in rules, on the reader every screen calls.
  describe "the batching" do
    def statements_for(&block)
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record", &block)
      statements
    end

    # Six item-backed dated rules on top of the two rate rules the fixture already carries, so both
    # lanes are populated and the adjustment table has a row per rule to group.
    def plant_six_more_rules
      6.times do |n|
        item = create(:item, category: groceries, name: "Bill #{n}")
        rule = create(
          :budget,
          category: groceries,
          item: item,
          amount: 100,
          interval_months: 6,
          anchor_date: Date.new(2026, 6, 1)
        )
        create(:adjustment, rule: rule, amount: 10, date: Time.utc(2026, 6, 10, 12))
      end
    end

    it "reads both spending lanes and the deltas once each", :aggregate_failures do
      plant_six_more_rules
      # Re-found rather than reused: the fixture's own user carries loaded associations, which would
      # answer some of the walk out of memory and hide the very statements this pins.
      fresh = described_class.new(User.find(user.id), today: today)

      sql = statements_for { fresh.total_claims }

      expect(sql.grep(/FROM "entries"/).size).to eq(2)
      expect(sql.grep(/FROM "adjustments"/).size).to eq(1)
    end
  end
end
