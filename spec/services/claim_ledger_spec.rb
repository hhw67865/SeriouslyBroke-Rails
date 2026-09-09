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
      funded_since: Date.new(2026, 1, 1)
    )
  end
  let(:groceries_rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }
  # ** A GOAL — $1,200 BY AUG 31, WHICH IS A DATED RULE AND NOTHING ELSE (two-shapes spec §2 row 5). **
  # Eight monthly periods from the funding day, so §3.2's catch-up share is `1,200 ÷ 8` = $150 every
  # period and the goal is whole by August. It was a $150-a-period rule that carried its money over
  # and stopped at $1,200; the walk's figures are identical, which is what let the shape be retired
  # rather than replaced.
  let(:vacation_rule) do
    create(
      :budget,
      category: vacation,
      amount: 1_200,
      basis: :monthly,
      interval_months: nil,
      anchor_date: Date.new(2026, 8, 31),
      created_at: born
    )
  end
  let(:ledger) { described_class.new(user, today: today) }

  # $3,000 in on Jan 5, $1,000 of it moved to Ally, $250 of groceries on Sep 2.
  #   pot          = 3000 − 250 − 1000 = 1750
  #   total_money  = 1750 + 1000       = 2750
  #   Groceries    = 400 − 250         =  150
  #   Vacation     = 8 periods × 150, whole at the rule's own 1,200
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

  # ===========================================================================================
  # ** `free = pot − Σ claims` (two-shapes spec §2), AND THE TERM THAT LEFT IS THE POINT. **
  #
  # It was `min(pot, total_money − Σ claims)`: money in OTHER accounts was folded into the
  # subtraction and the answer was then capped at the pot, so for every user whose savings covered
  # their rules the two hero figures were the same number and the claims were invisible in the one
  # figure that is about them (Henry, 2026-09-05). Money elsewhere is now shown and never subtracted
  # from or added to anything, and `free` answers one question: of the money in CHECKING, how much is
  # not claimed.
  #
  # BOTH DIRECTIONS, and the second is the one the cap used to hide.
  # ===========================================================================================
  describe "#free" do
    # 1,750 in checking, 1,350 claimed. `#total_money` is asserted beside it because it still exists
    # and is a DIFFERENT question — what the user physically has everywhere — and this is the one
    # place the two are shown apart.
    it "is the pot less every claim", :aggregate_failures do
      expect(ledger.total_money).to eq(2_750)
      expect(ledger.free).to eq(400) # 1,750 − 1,350
    end

    # ** MONEY IN ANOTHER ACCOUNT MOVES IT BY THE AMOUNT THAT LEFT CHECKING, AND BY NOTHING ELSE. **
    # Another $1,000 walked over to Ally takes the pot to $750 and leaves every claim exactly where it
    # was, so `free` is −$600. Under the cap it read $750 — the whole pot, with $1,350 of rules
    # claiming against it, reported as free to spend.
    it "falls by what leaves checking, whatever the other accounts hold" do
      create(
        :account_movement,
        from_pool: user.default_account,
        to_pool: ally,
        amount: 1_000,
        date: Time.utc(2026, 1, 7, 12)
      )

      expect(ledger.free).to eq(-600) # 750 − 1,350
    end

    # ** THE ARM THE CAP ERASED, AT THE SIZE IT SHOWS UP AT. ** $10,000 arriving in Ally covers every
    # claim the user has several times over, so the old `total_money − Σ claims` was far above the pot
    # and the cap answered the POT ITSELF — $1,750, "free to spend", with $1,350 of rules claiming
    # against it and nothing on the screen saying so. What is true of CHECKING is unchanged by any of
    # it, which is the sentence the figure now makes.
    # $10,000 EARNED AND WALKED STRAIGHT OUT, so the pot ends exactly where it started and Ally holds
    # the lot: the one movement that changes what the user HAS everywhere without changing what is in
    # checking.
    it "is unmoved by $10,000 arriving in another account", :aggregate_failures do
      expect(ledger.free).to eq(400)
      earn(10_000, on: Date.new(2026, 1, 7))
      create(:account_movement, from_pool: user.default_account, to_pool: ally, amount: 10_000, date: Time.utc(2026, 1, 8, 12))
      after = described_class.new(user, today: today)

      expect(after.total_money).to eq(12_750)
      expect(after.free).to eq(400)
    end

    # ** BELOW ZERO IS A SIGNAL, NEVER A REFUSAL (§4). ** A $5,000 bill due Oct 1 on a category funded
    # this month claims half of itself now — two periods to fill it, this one and the Oct one — and
    # the user is $2,100 short of what their rules claim out of checking.
    it "goes negative rather than clamping when the claims outrun the money", :aggregate_failures do
      car = create(:category, :expense, user: user, name: "Car", funded_since: Date.new(2026, 9, 1))
      create(:budget, category: car, amount: 5_000, interval_months: nil, anchor_date: Date.new(2026, 10, 1), created_at: Time.utc(2026, 9, 1, 9, 0))

      expect(ledger.total_claims).to eq(3_850)
      expect(ledger.free).to eq(-2_100) # 1,750 − 3,850
    end
  end

  # ===========================================================================================
  # ** THE LANE PARTITION, PRICED (§3.1/§3.2, ruling of 2026-09-03). ** The reviewer's scenario, in
  # money: Groceries carries a $400 catch-all rate rule AND a $600 bill on its own Vet item, and $300
  # of that bill is paid.
  #
  #   correct — the payment lowers the BILL's built-up by $300 and nothing else. Σ claims falls $300,
  #             total money falls $300, and the two move together, so `total − Σ claims` is unchanged.
  #   the bug — the catch-all's lane CONTAINED the Vet item, so the payment lowered both claims:
  #             Σ claims fell twice while the money fell once, and paying a bill made the app report
  #             MORE free money than before it was paid.
  #
  # The walk, so the literals are checkable: the bill is due Dec 1, the category has held since Jan 1
  # and the rule was born with it, so the catch-up formula puts $50 a period into it —
  # Jan (600−0)/12 = 50, Feb (600−50)/11 = 50, … eight periods to $400 by August, and September's
  # (600−400)/4 = 50 takes it to $450 before any payment.
  # ===========================================================================================
  describe "a catch-all rule beside an item-backed one" do
    # THE BILL EXISTS IN EVERY EXAMPLE HERE, including the two that never name it: `free` is a figure
    # about the WHOLE rule set, so a fixture that planted the bill lazily would price a different
    # user in the examples that only read the total.
    before { vet_rule }

    # $300 of the vet bill, paid on Sep 2 — the same day and the same period as the fixture's $250 of
    # ordinary groceries, so nothing here is separated by the calendar.
    def pay_the_vet_bill
      create(:entry, item: vet_item, amount: 300, date: Date.new(2026, 9, 2))
    end

    def vet_item
      @vet_item ||= create(:item, category: groceries, name: "Vet")
    end

    def vet_rule
      @vet_rule ||= create(:budget, category: groceries, item: vet_item, amount: 600, interval_months: 12, anchor_date: Date.new(2026, 12, 1), created_at: born)
    end

    it "builds the bill up on its own item and leaves the catch-all rule alone", :aggregate_failures do
      expect(ledger.calculator_for(vet_rule).built_up).to eq(450)
      expect(ledger.claim_of(groceries_rule)).to eq(150) # $400 rate less the fixture's $250
      expect(ledger.total_claims).to eq(1_800) # 150 + 1,200 Vacation + 450
    end

    # ** THE PAYMENT, PRICED. ** Only the bill's fund moves, and Σ claims and total money move
    # together — which is the whole of what the partition buys.
    it "lowers only the item rule's built-up when the bill is paid", :aggregate_failures do
      pay_the_vet_bill

      expect(ledger.calculator_for(vet_rule).built_up).to eq(150) # 450 − 300
      expect(ledger.claim_of(groceries_rule)).to eq(150) # unchanged: the Vet item is not its lane
      expect(ledger.total_claims).to eq(1_500) # 1,800 − 300
      expect(ledger.total_money).to eq(2_450) # 2,750 − 300
    end

    # ** THE DISCRIMINATING HALF, AND `free = pot − Σ claims` SHARPENS IT (two-shapes §2). ** The
    # payment takes $300 out of checking and $300 off the bill's fund, so both terms fall together and
    # `free` does not move at all. Under the double-counted lane Σ claims fell by $450 against $300 of
    # money and free ROSE $150 for having paid a bill — which the cap could mask and this cannot.
    it "leaves free where it was, because the money and the claims fell together", :aggregate_failures do
      expect(ledger.free).to eq(-50) # 1,750 pot − 1,800 claimed
      pay_the_vet_bill

      expect(described_class.new(user, today: today).free).to eq(-50) # 1,450 − 1,500
    end

    # ** AND MONEY WALKED OUT TO ANOTHER ACCOUNT MOVES IT BY EXACTLY WHAT LEFT. ** $1,000 to Ally
    # takes free down $1,000 and touches no claim; the payment on top of it still moves nothing,
    # because both terms fall together whatever the pot happens to be.
    it "falls by what leaves checking and not by what a bill costs", :aggregate_failures do
      create(:account_movement, from_pool: user.default_account, to_pool: ally, amount: 1_000, date: Time.utc(2026, 1, 7, 12))

      expect(ledger.free).to eq(-1_050) # 750 − 1,800
      pay_the_vet_bill

      expect(described_class.new(user, today: today).free).to eq(-1_050) # 450 − 1,500
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
