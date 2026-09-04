# frozen_string_literal: true

require "rails_helper"

# THE DEMO IS INFRASTRUCTURE, so it gets a spec.
#
# `db/seeds.rb` is what every visual check on this plan is performed against and what `bin/ci`
# replants on every run, and since the distribution was dropped it is also a CLAIM: that the demo
# speaks the COMPUTED-CLAIM language natively — accounts, categories, rules, dated adjustments and
# account movements, and not one construct from the pool layer or from the distribution, neither of
# which has columns to be written into any more.
#
# THE CLAIM IS CHECKED IN BOTH DIRECTIONS, and that is the point of the file-level half. Grepping
# the source catches a legacy construct written into the seeds; asserting the database catches one
# that arrives through a factory, an association callback or a default. Either half alone can be
# satisfied by a file that does the wrong thing somewhere the other cannot see.
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL, and since the purpose side became a computation the
# working is written beside each one — `spec/services/claim_calculator_spec.rb`'s rule, applied to a
# fixture the seeds build rather than one the example does. Reading a claim out of the same
# calculator the app uses would assert that `ClaimCalculator` equals itself; these numbers are the
# demo's state table — the one in `db/seeds.rb`'s own header, beside the data it describes — written
# down where a change to the seeds has to argue with them.
#
# LOADING THE SEEDS PER EXAMPLE is deliberate and costs about a second. `before(:context)` would
# put ~200 rows outside the per-example transaction, where DatabaseCleaner cleans them out from
# under the group; the seeds are cheap enough that the honest version wins.
#
# ── DELETED WITH THE DISTRIBUTION (computed-claims spec §§5-6), named here because this file is the
# only place they were named and a deletion nobody records is a deletion nobody notices:
#
#   * "puts the household on a short waterfall with one alert" — it built a `DistributionPresenter`
#     and pinned `#available` at $1,900.00, `#short?`, `#expanded?`, one alert, twelve waterfall rows
#     and nineteen categories in the fill order. Every one of those readers is deleted: there is no
#     distribution, so there is no screen, no cutoff line and no alerts band. WHAT THE EXAMPLE WAS
#     REALLY ABOUT — this household's rules ask for more than it has — survives as `free < 0`, and
#     it is carried by "leaves the household short, and names who gives way" below, which asserts the
#     same fact through §2's definition instead of through a proposal nobody has to confirm.
#   * the purpose-side half of "conserves the bank balance across both ledgers", which asserted
#     `Σ holdings + available_at_the_root == 7_461.00` through `Category#status`. The purpose side is
#     no longer a partition (§2): `free = total_money − Σ claims` is a DEFINITION and claims are
#     derived, so there is nothing left to conserve and nothing for a second sum to disagree with.
#     The PHYSICAL half is untouched below, in the same raw SQL, against the same $7,461.00.
#   * `#available_at_the_root`, `#earned`, `#unheld`, `#allocated_out` and `#allocated_back` — five
#     helpers whose whole subject was the `allocations` table. The root is not computed from rows any
#     more; it is `ClaimLedger#free`, and "reports what the claims leave free" reads it.
#   * `row_counts[:allocations]` — the table is dropped. `:adjustments` takes its place in the same
#     hash, which is the demo's whole purpose-side write.
#
# The subject is a FILE, not a class, so there is no constant to hand `describe` — the same reason
# `spec/migrations/cutover_spec.rb` disables a path cop rather than renaming itself.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "db/seeds.rb" do
  # The seeds set `Time.zone` globally — they have to, or every datetime they write lands in UTC.
  # `use_zone` saves and restores the thread-local around the example, so the assignment the seeds
  # make inside is undone rather than leaked into whatever example runs next.
  around { |example| Time.use_zone(Time.zone) { example.run } }

  let(:source) { Rails.root.join("db/seeds.rb").read }

  # THE CODE ALONE, WITH EVERY COMMENT STRIPPED. The seeds' header explains at length what the pool
  # layer and the distribution WERE, so a grep over the raw file finds `Allocation` in prose and
  # fails on a sentence rather than on a construct. What this file polices is what the demo WRITES.
  let(:code) { source.lines.reject { |line| line.strip.start_with?("#") }.join }
  let(:user) { User.find_by!(email: "demo@example.com") }
  let(:today) { Time.find_zone!(user.timezone).today }

  def replant
    load Rails.root.join("db/seeds.rb")
  end

  # ONE LEDGER FOR THE WHOLE EXAMPLE, on `ClaimLedger`'s own rule: it is a snapshot, and two of them
  # over one replant would be two readings of the same rules free to disagree.
  def ledger = @ledger ||= ClaimLedger.new(user, today: today)

  # ONE RULE, BY THE CATEGORY THAT OWNS IT AND THE ITEM IT NAMES. `item_id: nil` is the catch-all
  # rule whose lane is the whole category (§3.1's partition), which is the one every set-aside below
  # lands on and the one a rate row is about.
  def rule_for(category_name, item_name = nil)
    category = user.categories.find_by!(name: category_name)
    item = item_name && category.items.find_by!(name: item_name)
    Budget.find_by!(category: category, item_id: item&.id)
  end

  def claim_of(category_name, item_name = nil) = ledger.calculator_for(rule_for(category_name, item_name))

  # Every table the demo writes to, in one reading — so the count example and the migration's
  # byte-identical check ask the same question of the same tables rather than two hand-kept lists.
  #
  # `allocations` IS GONE AND `adjustments` HAS TAKEN ITS PLACE (computed-claims §5). The one is not
  # a rename of the other: the demo used to write 61 allocation rows, most of them the distribution
  # funding a rule it can now compute, and what is left is the 28 hand set-asides §3.3 keeps.
  def row_counts
    {
      users: User.count,
      pools: Pool.count,
      categories: Category.count,
      items: Item.count,
      entries: Entry.count,
      budgets: Budget.count,
      movements: AccountMovement.count,
      adjustments: Adjustment.count
    }
  end

  # THE INTEGER THE SCHEMA HOLDS TODAY, not `Category.savings`. `category_type: 2` was deleted from
  # the enum in plan 3, and this assertion has to outlive that: a spec that stopped compiling the
  # moment the legacy value went away would stop guarding the seeds exactly when the guard became
  # cheap to break. A method rather than a constant because a constant declared in a block leaks out
  # of the example group.
  def savings_category_type = 2

  describe "the file itself" do
    it "never writes a pool that is not an account", :aggregate_failures do
      expect(code).not_to match(/pool_type:\s*:(budget|savings)/)
      expect(code).not_to match(/\baccount:\s/)
    end

    it "never names a column the drop deleted", :aggregate_failures do
      expect(code).not_to match(/\bpool_id\b/)
      expect(code).not_to match(/\bstart_date\b/)
      expect(code).not_to match(/\bPoolMovement\b/)
    end

    # ** THE DISTRIBUTION'S OWN VOCABULARY, WHICH THE DEMO MAY NO LONGER SPEAK (§§5-6). ** Every name
    # here is a class or a local the seeds actually used one commit ago — `Allocation.create!` in the
    # `allocate` builder, `Allocation` at the head of the truncation loop — and every one of them is
    # deleted code now. A grep is the cheap half of the promise: a `require`-less `load` of a file
    # naming a missing constant fails loudly, but a local called `allocate` that wrote something
    # ELSE would not, and neither would a comment-free reintroduction of the word on a screen.
    it "never writes a construct the distribution took with it", :aggregate_failures do
      expect(code).not_to match(/\bAllocation\b/)
      expect(code).not_to match(/\ballocate\b/)
      expect(code).not_to match(/\bholding_calculator\b/)
      expect(code).not_to match(/\bHoldingStatus\b/)
      expect(code).not_to match(/\bDistributionPresenter\b/)
      expect(code).not_to match(/\bdistribute\b/)
    end

    # ** EVERY RULE GOES THROUGH THE ONE BUILDER, AND THE BUILDER IS WHAT BACKDATES ITS BIRTHDAY. **
    # `ClaimCalculator#accrual_start` is `max(funded_since, the rule's own creation day)`, so a rule
    # written by the seed run itself walks a single period and every fund on the demo reads $0.00
    # built up. `db/seeds.rb`'s `rule` lambda stamps `created_at: demo_start`; a bare
    # `Budget.create!` beside it would be a rule that silently opts out of six months of history, and
    # the failure would look like a wrong figure rather than like a missing keyword.
    #
    # ONE `Budget.create!` IN THE WHOLE FILE, AND IT IS THE BUILDER'S OWN BODY. Counting it rather
    # than forbidding the string is the only spelling that can tell the builder from a rule written
    # around it.
    #
    # EIGHTEEN CALL SITES FOR TWENTY-ONE RULES: the four hand-fed goals are written by one call
    # inside a loop, because their shape is identical and four copies of a zero-amount rule is four
    # places for one ruling to be edited.
    it "writes every rule through the builder that backdates it", :aggregate_failures do
      written = code.scan(/rule\.call\((?:[^()]|\([^()]*\))*\)/m)

      expect(code.scan("Budget.create!").length).to eq(1)
      expect(written.length).to eq(18)
      expect(written.reject { |call| call.include?("category:") }).to eq([])
    end

    # ** A TARGET IS A RULE'S, AND THE GREP IS THE ONLY HALF THAT CAN SAY SO (rules-own-the-budget
    # §6/§7). ** `categories.target_amount` is dropped, so a seed writing one would raise on the
    # replant and the database half below would catch it — but a seed writing the figure onto the
    # CATEGORY through some other spelling would not, and neither would a reviewer skimming past a
    # `target:` keyword on the holder builder. Every `target_amount` in the file has to sit inside a
    # `rule.call`, which is what this asks: strip the rule calls out and nothing is left.
    it "names a target only on a rule" do
      outside_the_rules = code.gsub(/rule\.call\((?:[^()]|\([^()]*\))*\)/m, "")

      expect(outside_the_rules).not_to include("target_amount")
    end

    # ** EVERY RULE NAMES ITS OWN TYPE (§3). ** `budgets.rule_type` is NOT NULL with a `usage`
    # default, so a rule that said nothing would still save — and would then read `usage` on the
    # Budget page and give way second whatever the demo meant by it. The default exists for rows
    # written before the column did (§6 step 3); this file writes none of those, so an untyped call
    # here is an opinion nobody stated rather than a legacy row.
    it "types every rule it writes" do
      written = code.scan(/rule\.call\((?:[^()]|\([^()]*\))*\)/m)

      expect(written.reject { |call| call.include?("rule_type:") }).to eq([])
    end

    it "never writes a savings category", :aggregate_failures do
      expect(code).not_to match(/category_type:\s*:savings/)
      expect(code).not_to match(/lane\.call\([^)]*:savings/)
    end
  end

  describe "the database after a replant" do
    before { replant }

    it "holds exactly the rows the demo is made of" do
      expect(row_counts).to eq(
        users: 1,
        # 29 SINCE `Streaming` (computed-claims Task 3's band). A category with no holding date
        # carrying a rule is the one shape `BudgetPagePresenter#unfilled_rules` renders, and the
        # demo had none while every rule's category was a holder.
        categories: 29,
        pools: 4,
        # 25 SINCE THE VET ITEM (the rulings of 2026-09-03). Pet Care is the demo's MIXED case — a
        # rate rule beside a dated bill — and both of those rulings land on it: a category may carry
        # only ONE rule whose lane is the whole of it, so the vet bill has to name an item, and the
        # lane PARTITION then keeps the bill's payments out of the rate rule's figure.
        items: 25,
        entries: 75,
        # 21 = the 16 the two-ledger demo carried, plus the four target-only rules the hand-fed goals
        # need under §3.3 ("every adjustment targets a rule"), plus Streaming's.
        budgets: 21,
        movements: 8,
        # 28 = four goals × seven periods, and nothing else. The other 33 rows the demo used to
        # write were the distribution funding rules the app now computes (see the seeds' header).
        adjustments: 28
      )
    end

    it "writes no savings category and no savings entry", :aggregate_failures do
      savings_categories = Category.where(category_type: savings_category_type)

      expect(savings_categories.count).to eq(0)
      expect(Entry.joins(item: :category).where(categories: { category_type: savings_category_type }).count).to eq(0)
    end

    # EVERY POOL IS AN ACCOUNT AND EVERY RULE HAS AN OWNER, plus the pot itself, which every entry
    # lands in.
    #
    # EXACTLY ONE RULE'S CATEGORY IS NOT A HOLDER, and it is planted rather than tolerated: that is
    # the Budget page's "Not in the give-way order" band, whose whole subject is a rule claiming its
    # full amount every period while nothing spent in its category ever comes off it.
    it "writes accounts, holders, one unfilled rule and a nominated pot", :aggregate_failures do
      expect(Pool.where.not(pool_type: :account).count).to eq(0)
      expect(Budget.where(category_id: nil).count).to eq(0)
      expect(Budget.all.reject { |rule| rule.category.holder? }.map { |rule| rule.category.name }).to eq(["Streaming"])
      expect(user.default_account).to eq(Pool.find_by!(name: "Checking"))
    end

    # ** THE PHYSICAL INVARIANT, AND IT IS THE ONLY ONE LEFT (§2). ** `pot + Σ accounts == income −
    # expenses`: every dollar the bank says the household has is sitting in exactly one account. The
    # purpose side is not a partition any more — claims are derived, so there is no second sum to
    # reconcile — and the example that asserted one is named at the head of this file.
    #
    # `::numeric` on the entry arms: `money` is a fixed-scale Postgres type with no unary minus at
    # all, so the expense arm is a type error rather than a wrong figure.
    it "conserves the bank balance", :aggregate_failures do
      account_ledger = AccountLedger.new(user)
      physical = user.pools.accounts.sum(0.to_d) { |account| account_ledger.balance_of(account) }
      bank = user.entries.joins(item: :category).sum(
        "CASE WHEN categories.category_type = 1 THEN entries.amount::numeric ELSE -entries.amount::numeric END"
      )

      expect(bank).to eq(7_461.00)
      expect(physical).to eq(7_461.00)
    end

    # ** §2'S DEFINITION, ON THE DEMO: `free = min(pot, total_money − Σ claims)`. **
    #
    #   total_money   $7,461.00   the physical invariant above, unchanged
    #   − Σ claims   $10,201.34   over all 21 rules — the sum of the figures the examples below pin
    #   = unclaimed  -$2,740.34   which is BELOW the pot, so the `min` does not bind
    #
    # FREE IS NEGATIVE, AND THAT IS THIS DEMO'S INHERITANCE RATHER THAN A NEW PESSIMISM. The deleted
    # waterfall example asserted `short?` for the same household on the same data: its rules ask for
    # more than it has. §4 says that is a SIGNAL and never a refusal, so the trouble strip states the
    # figure, walks the uncovered claims in reverse priority and names the per-day pace — which is
    # the branch this demo exists to put on a screen, exactly as the cutoff line was before it.
    it "reports what the claims leave free", :aggregate_failures do
      expect(ledger.total_money).to eq(7_461.00)
      expect(ledger.pot).to eq(5_561.00)
      expect(ledger.total_claims).to eq(10_201.34)
      expect(ledger.free).to eq(-2_740.34)
      expect(ledger.free_cap_bound?).to be(false)
    end

    # ** §3.1, ALL THREE WAYS A RATE ROW CAN READ, ON THE MORNING THE PERIOD OPENS. **
    # `claim = max(0, rate + Σ this period's deltas − spent this period)`, and the demo carries no
    # deltas on a rate rule, so each of these is `rate − spent`:
    #
    #   Household Supplies   120 − 45  = 75.00    UNDER — today's detergent run
    #   Dining Out           100 − 110 = -10 → 0  OVER  — the claim clamps, `over?` reads the -10
    #   Groceries            400 − 0   = 400.00   UNTOUCHED — nothing has been spent yet
    #
    # THE PERIOD IS ANCHORED ON TODAY, so today is its only elapsed day and the two figures that are
    # not zero belong to entries dated `today`. That is what makes this a three-state example rather
    # than three readings of zero.
    it "puts a rate rule under its rate, over it, and untouched", :aggregate_failures do
      expect([claim_of("Household Supplies").spent_this_period, claim_of("Household Supplies").claim]).to eq([45, 75])
      expect([claim_of("Dining Out").spent_this_period, claim_of("Dining Out").claim]).to eq([110, 0])
      expect(claim_of("Dining Out").over?).to be(true)
      expect([claim_of("Groceries").spent_this_period, claim_of("Groceries").claim]).to eq([0, 400])
      expect(claim_of("Groceries").over?).to be(false)
    end

    # ** §3.2, A FUND BUILDING UP TOWARD A DATE. ** The walk runs from `demo_start` — six months
    # back, which is where every rule is born (see the seeds' header) — and each period's share is
    # the catch-up formula, `(target − built up before this period) ÷ periods left including this
    # one`, so the fund lands whole ON the day rather than after it.
    #
    #   RENT             $1,500 a month on the Monthly Rent item, next due ten days out. Three
    #                    payments have gone through the walk and each was a FULFILMENT that dropped
    #                    the fund and rolled the cycle; the fund is whole again for the fourth,
    #                    because with one boundary left before the date `periods_left` is 1 and this
    #                    period's share IS the whole remaining gap.
    #   QUARTERLY TAXES  $1,800 every three months, due two months out, nothing ever spent. Two
    #                    months out is between 59 and 62 days, so the boundaries left from the
    #                    opening of period k back are `k + 5` on every run day, and the walk starts
    #                    at k = 13 (`demo_start` is thirteen periods back, which is why it is a
    #                    boundary and not `6.months`): $1,800 ÷ 18 = $100.00, and the share stays
    #                    $100.00 every period because the gap and the divisor fall together.
    #                    Fourteen periods × $100.00 = $1,400.00 built up, $400.00 still to find.
    it "builds the dated funds up toward their dates", :aggregate_failures do
      rent = claim_of("Rent", "Monthly Rent")
      taxes = claim_of("Quarterly Taxes")

      expect([rent.built_up, rent.target, rent.next_due_on]).to eq([1_500, 1_500, today + 10])
      expect(rent.overdue?).to be(false)
      expect([taxes.built_up, taxes.target, taxes.next_due_on]).to eq([1_400, 1_800, today + 2.months])
      expect(taxes.planned_this_period).to eq(100)
    end

    # ** THE CATCH-UP FORMULA IS NOT `target ÷ periods`, AND THIS IS THE EXAMPLE THAT SAYS SO. **
    # Car Insurance is $1,200 six-monthly with its next occurrence ONE MONTH out — between 28 and 31
    # days, so there are always exactly three boundaries left from the current period's open and
    # `k + 3` from period k back. The walk opens at k = 13 with sixteen periods left and asks for
    # $1,200 ÷ 16 = $75.00; every period afterwards the gap has fallen by $75.00 and the divisor by
    # one, so the share stays $75.00 — and after fourteen periods the fund holds $1,050.00 with
    # $150.00 to find over the three periods that are left. Divided flat over the walk it would read
    # $1,200 ÷ 14 = $85.71 a period, which is a different rule.
    it "recomputes the per-period share rather than dividing the target flat", :aggregate_failures do
      car = claim_of("Car Insurance")

      expect([car.built_up, car.target]).to eq([1_050, 1_200])
      expect(car.planned_this_period).to eq(75)
      expect(car.periods_left).to eq(3)
      expect(car.next_due_on).to eq(today + 1.month)
    end

    # ** §3.2'S OVERDUE: A DATE THAT PASSED WITH NOBODY PAYING IT. ** The cycle rolls on PAYMENT and
    # never on the calendar (`ClaimCalculator#due_on`), and the Renters Policy item has no entry at
    # all — so `cycles paid` is zero, the occurrence stays anchored six days back, and
    # `next_due_on < today` is `#overdue?` verbatim.
    #
    # THE FUND IS WHOLE, WHICH IS THE ORDINARY SHAPE OF AN OVERDUE BILL rather than the exception:
    # the catch-up formula floors `periods left` at 1 for a date already past, so an unpaid fund
    # fills in ONE period. That is what makes the strip say "it's all there — pay it and the fund
    # starts again"; the trigger is the date, not the money.
    #
    # AND THE ELECTRIC BILL IS NOT OVERDUE THOUGH ITS ANCHOR IS OLDER, which is the other half of
    # the same sentence: three $120 bills have been paid since `demo_start`, so one whole cycle is
    # settled and the next occurrence is a month past the anchor.
    it "leaves the renters premium overdue with the money already there", :aggregate_failures do
      renters = claim_of("Renters Insurance", "Renters Policy")

      expect(renters.next_due_on).to eq(today - 6)
      expect(renters.overdue?).to be(true)
      expect([renters.built_up, renters.target]).to eq([180, 180])
      expect(claim_of("Utilities", "Electric Bill").overdue?).to be(false)
    end

    # ** §3.2'S TWO DATELESS SHAPES, ONE OF EACH. **
    #
    #   FED BY HAND     Emergency Fund's rule has an amount of ZERO — "no rate", the only honest way
    #                   to say a goal has no standing contribution (`Budget#set_aside_only?`) — so
    #                   its planned accrual is $0.00 every period and the seven $100 set-asides are
    #                   the WHOLE of what it holds: 7 × 100 = $700.00. This is the shape
    #                   `DropTheDistribution#mint_rule` mints, column for column.
    #   FED BY A RULE   Vacation to Europe accrues $50 a period toward $5,000 with no deadline to
    #                   spread it over, and the $180 flight deposit was a FULFILMENT that came
    #                   straight off the built-up. Fourteen periods from `demo_start` × $50 = $700,
    #                   less the $180 = $520.00.
    #
    # THE SET-ASIDES ARE DATED ACROSS SEVEN PERIODS AND EVERY ONE COUNTS, which is the accrual-span
    # ruling doing its work: the rules are born on `demo_start`, so `#countable_span` opens six
    # months back and each row lands in the period containing its date (§3.3). Born at seed time
    # instead, this figure would be $100.00 — one period's worth — and the example would still read
    # like a savings goal.
    it "feeds four goals by hand and one by its rule", :aggregate_failures do
      emergency = claim_of("Emergency Fund")
      vacation = claim_of("Vacation to Europe")

      expect(emergency.planned_this_period).to eq(0)
      expect([emergency.built_up, emergency.target]).to eq([700, 10_000])
      expect(emergency.countable_span.first).to eq(today - (13 * 14))
      expect([vacation.built_up, vacation.target]).to eq([520, 5_000])
    end

    # THE SAME FOUR GOALS FROM THE OTHER SIDE — the rows themselves, grouped by the category they
    # feed, so a set-aside that landed on the wrong rule cannot hide inside a built-up figure that
    # happens to come out right.
    it "writes every hand-fed goal's set-asides against its own rule" do
      expect(Adjustment.joins(rule: :category).group("categories.name").sum(:amount)).to eq(
        "Emergency Fund" => 700,
        "House Down Payment" => 1_050,
        "New Car" => 525,
        "Retirement Supplement" => 1_050
      )
    end

    # ** THE BUDGET PAGE'S "NOT IN THE GIVE-WAY ORDER" BAND. ** `Category.in_fill_order` is holders
    # only, so a rule on a category with no holding date cannot be ranked and cannot be dragged —
    # while `ClaimLedger` counts it into `#free` like every other rule. $25.00 claimed every period
    # against spending that is attributed to nobody: the asymmetry the band exists to name.
    it "leaves one rule outside the give-way order", :aggregate_failures do
      page = BudgetPagePresenter.new(user: user, today: today)

      expect(page.unfilled_rules.map { |rule| rule.budget.category.name }).to eq(["Streaming"])
      expect(page.unfilled_rules.sole.claim).to eq(25)
    end

    # ** FREE BELOW ZERO IS A SIGNAL (§4), AND THE STRIP SAYS WHO GIVES WAY. ** The walk runs
    # `HomePresenter#give_way_order` — TYPE first (choice, then usage, then bill), and inside a type
    # the highest priority number first, which is `#budgeted_categories` read backwards — taking each
    # rule's claim until the $2,740.34 is absorbed:
    #
    #   Retirement Supplement  1,050.00   choice, priority 19, the demo's last, so it yields first
    #   New Car                  525.00   choice, 18
    #   Vacation to Europe       520.00   choice, 16
    #   Holiday Gifts            645.34   choice, 11 — PARTIAL, and the whole reason this is a walk
    #                                     rather than a filter: "$645.34 of it is uncovered" is a
    #                                     different sentence from "Holiday Gifts is uncovered", and
    #                                     only the walk can tell them apart
    #   ────────────────────   2,740.34   which is the headline exactly, so `#uncovered_remainder`
    #                                     is zero and no part of the shortfall goes unnamed
    #
    # ** THE LIST CHANGED WITH THE TYPES AND THE HEADLINE DID NOT (rules-own-the-budget §3). ** It
    # used to read Retirement, New Car, House Down Payment and $115.34 of Vacation, on priority
    # alone. `db/seeds.rb` types House Down Payment `usage` and Emergency Fund `bill`, so both now
    # rank behind every discretionary rule the household has and the walk reaches Holiday Gifts
    # instead — four `choice` rules absorbing the same $2,740.34 at the same $210.80 a day.
    #
    # NO BILL IS TOUCHED, which is what a give-way order is for: this household's discretionary
    # saving is what gives, and the rent — and now the emergency fund — is never in the list.
    it "leaves the household short, and says so on every reader the strip renders", :aggregate_failures do
      home = HomePresenter.new(user: user, today: today)

      expect(home.short?).to be(true)
      expect(home.claims_outrun_the_money?).to be(true)
      expect(home.shortfall).to eq(2_740.34)
      expect(home.per_day_pace).to eq(210.80)
      expect(home.troubles.map(&:kind)).to eq([:overdraft, :shortfall, :over, :overdue, :structural])
    end

    # ** AND WHO GIVES WAY, WHICH IS THE HALF THE FIGURE ABOVE CANNOT SAY. ** Type decides before
    # priority does (§3), so the walk is the household's four `choice` rules in reverse priority and
    # they absorb the whole $2,740.34 — the last of them PART-COVERED at $645.34, which is why
    # `#uncovered_remainder` is zero and no part of the shortfall goes unnamed.
    #
    it "names the four discretionary rules that give way, the last part-covered", :aggregate_failures do
      home = HomePresenter.new(user: user, today: today)

      expect(home.uncovered_claims.map { |claim| [claim.category.name, claim.amount] }).to eq(
        [
          ["Retirement Supplement", 1_050],
          ["New Car", 525],
          ["Vacation to Europe", 520],
          ["Holiday Gifts", 645.34]
        ]
      )
      expect(home.uncovered_remainder).to eq(0)
    end

    # THE TWO TYPED FUNDS ARE ASSERTED ABSENT, because that is what the type bought: House Down
    # Payment is `usage` and Emergency Fund is `bill`, and both carry claims ($1,050.00 and $700.00)
    # large enough to have been in the list above under priority alone — House Down Payment was.
    it "leaves the funds typed usage and bill out of the give-way list" do
      home = HomePresenter.new(user: user, today: today)

      expect(home.uncovered_claims.map { |claim| claim.category.name })
        .not_to include("House Down Payment", "Emergency Fund")
    end

    # ** THE TYPE OVERVIEW (§3), WHICH IS THE OTHER THING THE TYPES BOUGHT. ** `BudgetPagePresenter
    # #type_overview` sums `Budget#steady_ask` by type, so the three figures ADD to the $2,103.42
    # `Budget.steady_need` reports two examples down — the same sum, partitioned three ways. Planted,
    # and the sum asserted beside them so a partition that lost a rule could not pass.
    it "partitions the standing ask across the three types", :aggregate_failures do
      overview = BudgetPagePresenter.new(user: user, today: today).type_overview

      expect(overview).to eq([[:bill, 1_136.89], [:usage, 745.38], [:choice, 221.15]])
      expect(overview.sum { |_type, amount| amount }).to eq(2_103.42)
    end

    # ** THE NEED FELL $356.58 WHEN `BudgetCalculator` DIED (fix wave — MED-3). ** `#steady_ask`'s
    # one-off branch divided the WHOLE amount by the periods before the due date — asking for every
    # bill again from scratch, whatever was already saved toward it — and reached that divisor
    # through a class that also assumed every item-less bill was paid on time. The seeds' declared
    # income followed it down to $2,050 to keep the state this fixture exists to show. Both figures
    # are planted, and the verdict is asserted beside them so a pair that stopped straddling could
    # not pass.
    #
    # ** AND ONE CENT WHEN THE BRANCH BECAME A STANDING FIGURE (fix wave 2 — MED-A). ** It read
    # §3.2's catch-up share for one wave — what is still missing over the periods left, which moves
    # with every payment — and reads `ClaimCalculator#standing_ask` now, the amount over the periods
    # from the rule's birth to its due date. On this household the two nearly agree: both one-time
    # bills are as old as the seed and neither has been paid into, so only the Dentist's rounding
    # separates them ($21.43 a period against $21.42 — one division rounded once, against a division
    # rounded in each of fourteen periods). $2,103.41 → $2,103.42; the declaration does not move.
    it "leaves the household structurally underwater, so the sacrifice view has a screen", :aggregate_failures do
      expect(Budget.steady_need(user, today: today)).to eq(2_103.42)
      expect(user.typical_income).to eq(2_050.00)
      expect(HomePresenter.new(user: user, today: today)).to be_structurally_underwater
    end

    # `dated_bill: 3` WAS 6 (answers-first Home spec §7, the occurrence gate). Three of the six
    # were one-off spends — the Body Shop repair, the quarterly tax estimate — that the engine read
    # as annual bills and disclaimed as guesses in their own rows; that shape is deleted, so the
    # three MEASURED utility bills are what is left.
    #
    # ** NONE OF THESE FOUR FIGURES MOVED WHEN THE DISTRIBUTION DID, AND THAT IS HALF OF WHAT THIS
    # EXAMPLE NOW SAYS. ** `SuggestionEngine` reads ENTRIES and RULES and never read an allocation,
    # so dropping 33 funding rows moved nothing; what DID move is inside the demo's own choices, and
    # the two changed rows are Dining Out (a $100 rule where the pool era had $150, so the overspend
    # this period is reachable at all) and Household Supplies (its one receipt moved into today).
    #
    # WHICH FOUR DRIFT, AND WHY NOT MORE: Groceries (the one UPWARD suggestion, $460 a period against
    # a $400 rule), Dining Out, Household Supplies and Pet Care are the categories whose spending
    # genuinely diverges from their rules. Every other rate rule in the demo either has spending that
    # matches it or is dated instead — `db/seeds.rb` chooses those shapes deliberately, because a
    # rate rule on a category with no spending at all is drift's starkest sentence and four of those
    # would be four suggestions telling the demo user to zero rules they have not spent from yet.
    # ONE of them is planted on purpose (Household Supplies), and the seeds' header says why.
    it "feeds all four suggestion detectors" do
      kinds = SuggestionEngine.new(user: user, today: today).suggestions.group_by(&:kind)
        .transform_values(&:length)

      expect(kinds).to eq(dated_bill: 3, rate: 4, drift: 4, dead_rule: 1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
