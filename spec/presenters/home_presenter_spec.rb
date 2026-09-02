# frozen_string_literal: true

require "rails_helper"

# HOME, ON BOTH LEDGERS (two-ledger spec §2). This file was pool-shaped in every example: it planted
# envelopes inside accounts, filled one pot per account, and asserted an orphan apparatus. Task 6
# converted it whole, and the deletions are named at the describe blocks they used to sit in.
RSpec.describe HomePresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  # `checking` is the account this whole file treats as primary, and several examples mint a SECOND
  # account before ever touching it — the auto-main factory trait claims whichever account it sees
  # first for a user with none named. Forcing it here rather than disciplining every example's
  # creation order.
  before { user.update!(default_account: checking) }

  # A CATEGORY THAT HOLDS MONEY (spec §3): an expense category with a `funded_since`. The date is a
  # LITERAL and not `1.year.ago`, because this file's clock is fixed at Feb 2026 and a wall-clock
  # funding date would slide past it in a real year (CLAUDE.md's third flake cause).
  def holder(name, priority:, funded_since: Date.new(2025, 1, 1))
    create(:category, :expense, user: user, name: name, priority: priority, funded_since: funded_since)
  end

  # A GOAL IS A HOLDER WITH A TARGET (spec §3). `Category#savings?` additionally wants no rule, which
  # is the DISPLAY question; the examples below that hang a rate rule on one are asking the FUNDING
  # question, and `HoldingCalculator#dateless_goal?` answers it off the target alone.
  def savings_goal(name, priority:, target: 1_200)
    holder(name, priority: priority).tap { |category| category.update!(target_amount: target) }
  end

  # A flat per-period rule: the catch-all shape, and the one that makes `required` exactly the amount
  # asked for. `pool: nil` because a rule belongs to the thing that holds the money now.
  def rate(category, amount)
    create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
  end

  def bill(category, amount:, due:)
    create(:budget, :one_time, pool: nil, category: category, amount: amount, anchor_date: due)
  end

  # A rule that rolls: its due date moves with the cycles that have gone by, which is what makes it
  # depend on which day the calculator is asked about.
  def rolling(category, amount:, anchor:)
    create(:budget, pool: nil, category: category, amount: amount, interval_months: 1, anchor_date: anchor)
  end

  # INCOME RAISES BOTH LEDGERS AT ONCE (§2): the pot, and available. It lands in the user's main
  # account, which is the only place income may land.
  def income(amount, on: today)
    category = create(:category, :income, user: user, pool: checking, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # SPENDING LOWERS THE POT ALWAYS, and lowers the CATEGORY when the category counts that day —
  # otherwise it lowers available (§4's start-date rule).
  def spend(category, amount, on: today)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A BILL THAT ROLLS ONCE A YEAR: its whole face value falls due inside the current period, which
  # is what makes `total_required` and `Budget.steady_need` diverge.
  def annual(category, amount:, due:)
    create(:budget, pool: nil, category: category, amount: amount, interval_months: 12, anchor_date: due)
  end

  # A DATED BILL THE USER ACTUALLY PAYS: an item is the only fulfilment signal BudgetCalculator
  # accepts, and therefore the only way a rule can be overdue rather than merely settled by its date.
  def payable(name, amount:, due:, priority: 1)
    holder(name, priority: priority).tap do |category|
      item = create(:item, category: category, name: "#{name} Bill")
      create(:budget, :one_time, pool: nil, category: category, item: item, amount: amount, anchor_date: due)
    end
  end

  # AVAILABLE → A CATEGORY. The purpose ledger's only writer besides entries.
  def allocate(category, amount, on: today)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  describe "#accounts" do
    it "returns only this user's accounts, by name", :aggregate_failures do
      # `checking` is forced FIRST so insertion order is Checking, Ally — the reverse of the expected
      # answer. With Ally created first the rows come back alphabetically already, and dropping
      # `.order(:name)` would still pass.
      checking
      ally = create(:pool, :account, user: user, name: "Ally")
      holder("Groceries", priority: 1)
      create(:pool, :account, user: create(:user), name: "Someone Else")

      expect(presenter.accounts).to eq([ally, checking])
      expect(presenter.accounts.map(&:name)).to eq(["Ally", "Checking"])
    end
  end

  # ── DELETED (Task 6): the whole `#orphan_pools`, `#orphan_pools_owed`, `#orphan_required` and
  # `#pools_for` group, and the "#waterfall across accounts" describe (four examples: "funds each
  # envelope only from its own account", "is not covered when the money is in an account with no
  # envelopes", "drains each account's pot independently", "does not spend down the cash it reports
  # as available" — the last is re-asked below, because a single pot can still be spent down).
  #
  # ALL SIX READERS ARE GONE, and so is the shape every one of them was about. A category belongs to
  # no account and cannot be an orphan; allocating money moves nothing physical (§2), so there is no
  # per-account pot for money to be stranded in and nothing for `#pools_for` to nest.

  describe "#balance_of" do
    it "is what the bank says, and for main that is the pot", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      allocate(groceries, 400)

      # The allocation moves nothing physical, so the pot is untouched by it — which is the whole
      # of §2's "any account's money can back any category".
      expect(presenter.balance_of(checking)).to eq(1_000)
      expect(AccountLedger.new(user).pot).to eq(1_000)
    end

    it "is movements only on an account that is not main", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:pool_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

      expect(presenter.balance_of(ally)).to eq(600)
      expect(presenter.balance_of(checking)).to eq(400)
    end

    it "is a decimal zero, not an integer, on an empty account" do
      expect(presenter.balance_of(checking)).to be_a(BigDecimal)
    end
  end

  describe "#categories" do
    it "returns the holders in fill order and nothing else", :aggregate_failures do
      # Reverse alphabetical at a shared priority, so the name tie-break is visible; and two shapes
      # that are NOT holders — an income category, and an expense one that has never been funded.
      zoo = holder("Zoo", priority: 1)
      apples = holder("Apples", priority: 1)
      later = holder("Later", priority: 2)
      create(:category, :expense, user: user, name: "Never Funded", priority: 0)
      create(:category, :income, user: user, pool: checking, name: "Salary")

      expect(presenter.categories).to eq([apples, zoo, later])
    end
  end

  describe "#status_for" do
    let(:dentist) do
      holder("Dentist", priority: 1).tap { |category| bill(category, amount: 300, due: Date.new(2026, 2, 14)) }
    end

    # The whole reason this method exists. Asserted in BOTH directions: the second expectation proves
    # a bare `category.status` genuinely disagrees on this data, so the first is pinning the injected
    # day rather than passing by coincidence.
    it "computes against the injected day, not Date.current", :aggregate_failures do
      travel_to(Date.new(2026, 2, 20)) do
        expect(presenter.status_for(dentist).state).to eq(:wont_make_it)
        expect(dentist.status.state).not_to eq(:wont_make_it)
      end
    end

    it "memoises per category so a row does not rebuild its status" do
      first_call = presenter.status_for(dentist)

      expect(presenter.status_for(dentist)).to be(first_call)
    end

    it "keeps distinct categories on distinct statuses", :aggregate_failures do
      quiet = holder("Groceries", priority: 2)
      rate(quiet, 100)

      expect(presenter.status_for(dentist)).not_to be(presenter.status_for(quiet))
      expect(presenter.status_for(quiet).state).not_to eq(:wont_make_it)
    end
  end

  describe "#dated_rules_for" do
    # An expanded row prints one line per dated rule, earliest first. An anchorless rule has no date
    # to print, so it is not one of these lines — and a row whose rules are ALL anchorless renders
    # its own sentence instead of an empty box.
    it "returns the anchored rules earliest due first, and nothing else", :aggregate_failures do
      utilities = holder("Utilities", priority: 1)
      electric = bill(utilities, amount: 90, due: Date.new(2026, 3, 1))
      water = bill(utilities, amount: 40, due: Date.new(2026, 2, 20))
      rate(utilities, 25)

      expect(presenter.dated_rules_for(utilities)).to eq(
        [
          [water, Date.new(2026, 2, 20)],
          [electric, Date.new(2026, 3, 1)]
        ]
      )
    end

    it "is empty for a category funded only at a rate" do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)

      expect(presenter.dated_rules_for(groceries)).to be_empty
    end

    # The same hazard as #status_for, one level down. Asserted in BOTH directions — the second
    # expectation proves a bare `budget.calculator` genuinely disagrees on this data.
    it "dates a rolling rule against the injected day, not Date.current", :aggregate_failures do
      utilities = holder("Utilities", priority: 1)
      rule = rolling(utilities, amount: 120, anchor: Date.new(2026, 1, 1))

      travel_to(Date.new(2026, 6, 9)) do
        expect(presenter.dated_rules_for(utilities)).to eq([[rule, Date.new(2026, 3, 1)]])
        expect(rule.calculator.due_date).to eq(Date.new(2026, 7, 1))
      end
    end

    it "memoises per category so a row does not rebuild its rules" do
      utilities = holder("Utilities", priority: 1)
      bill(utilities, amount: 90, due: Date.new(2026, 3, 1))
      first_call = presenter.dated_rules_for(utilities)

      expect(presenter.dated_rules_for(utilities)).to be(first_call)
    end
  end

  describe "#available" do
    it "is money with no job yet" do
      income(2_400)

      expect(presenter.available).to eq(2_400)
    end

    it "drops what has been allocated to a category", :aggregate_failures do
      income(2_400)
      groceries = holder("Groceries", priority: 1)
      allocate(groceries, 400)

      expect(presenter.available).to eq(2_000)
      expect(CategoryLedger.new(presenter.categories, user: user).holding_of(groceries)).to eq(400)
    end

    # ONE ROOT, SO NO CLAMP (Task 6). The pool era clamped each account's pot at zero before summing,
    # because an overdrawn account cancelling a healthy one's surplus reports a number true about net
    # worth and false about what can be allocated. There is no sibling to cancel against now, so a
    # root that has been given out past what came in says so — exactly as AllocationCalculator#
    # available leaves it, and the two are now the same expression.
    it "states a negative root rather than rounding it up to nothing", :aggregate_failures do
      income(100)
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 500)

      expect(presenter.available).to eq(-400)
      expect(presenter.available).to eq(AllocationCalculator.new(user: user, today: today).available)
    end

    # THE SWEEP IS PART OF IT, and it is the half that keeps this screen and the distribute screen
    # naming one figure: a closed rate category's leftover is on its way back to the root, so a
    # headline that ignored it would understate what the button below is about to hand out.
    it "includes what the next distribution sweeps back", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      income(60, on: today - 25.days)
      allocate(groceries, 60, on: today - 20.days)

      # The $60 went out of the root last period and the rate period it belongs to has ended, so it
      # is on its way back: available reads $0 as the ledger stands and $60 as the button would find
      # it.
      expect(CategoryLedger.new(presenter.categories, user: user).available).to eq(0)
      expect(presenter.available).to eq(60)
      expect(presenter.available).to eq(AllocationCalculator.new(user: user, today: today).available)
    end

    it "is a decimal zero, not an integer, for a user with nothing", :aggregate_failures do
      expect(presenter.available).to eq(0)
      expect(presenter.available).to be_a(BigDecimal)
    end

    # A USER WITH NO HOLDERS AT ALL still has an available, and it is the first screen a new user
    # sees. `CategoryLedger` raises `NoSingleOwner` read off an empty category set, which is why the
    # presenter names the user when it builds one.
    it "answers for a user whose holder set is empty", :aggregate_failures do
      income(300)

      expect(presenter.categories).to be_empty
      expect(presenter.available).to eq(300)
    end
  end

  describe "#total_required" do
    it "sums what every holder needs this period" do
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Gas", priority: 2), 80)

      expect(presenter.total_required).to eq(480)
    end

    it "counts savings goals alongside spending categories", :aggregate_failures do
      rate(holder("Groceries", priority: 1), 400)
      rate(savings_goal("Vacation", priority: 2), 150)

      expect(presenter.total_required).to eq(550)
      expect(presenter.waterfall.map { |r| r[:category].name }).to eq(["Groceries", "Vacation"])
    end

    it "is a decimal zero, not an integer, for a user with no categories", :aggregate_failures do
      expect(presenter.total_required).to eq(0)
      expect(presenter.total_required).to be_a(BigDecimal)
      expect(presenter.shortfall).to be_a(BigDecimal)
    end
  end

  describe "#waterfall" do
    before do
      rate(holder("Rent", priority: 1), 500)
      rate(holder("Groceries", priority: 2), 400)
      rate(holder("Vacation", priority: 3), 150)
      income(700)
    end

    it "fills top-down by priority out of ONE root", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.map { |r| r[:category].name }).to eq(["Rent", "Groceries", "Vacation"])
      expect(rows[0][:funded]).to eq(500)
      expect(rows[1][:funded]).to eq(200)
      expect(rows[2][:funded]).to eq(0)
    end

    it "records each row's shortfall", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows[0][:short]).to eq(0)
      expect(rows[1][:short]).to eq(200)
      expect(rows[2][:short]).to eq(150)
    end

    it "reports the total gap", :aggregate_failures do
      expect(presenter.shortfall).to eq(350)
      expect(presenter).not_to be_covered
    end

    it "records what each row asked for, funded or not", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.pluck(:needed)).to eq([500, 400, 150])
      # `needed` is the ask, never the outcome: the cut-off row must still state its full
      # requirement, or the screen cannot show what running out actually cost.
      expect(rows.map { |r| r[:needed] - r[:funded] }).to eq(rows.pluck(:short))
    end

    # THE FILL IS AllocationCalculator'S, ASSERTED AS AN IDENTITY rather than as two matching lists
    # of literals: Home renders the proposal the distribute button would act on, and a screen that
    # disagreed with its own action is the defect this whole band is arranged to prevent.
    it "agrees with the proposal the distribute screen would render", :aggregate_failures do
      proposal = AllocationCalculator.new(user: user, today: today)

      expect(presenter.waterfall.map { |r| [r[:category].id, r[:needed], r[:funded]] })
        .to eq(proposal.rows.map { |row| [row.category.id, row.needed, row.funded] })
      expect(presenter.shortfall).to eq(proposal.rows.sum(&:short))
      expect(presenter.available).to eq(proposal.available)
    end

    it "does not spend down the cash it reports as available", :aggregate_failures do
      # The pot is spent down as the waterfall fills, so a `remaining` leaked into a memo would
      # leave #available summing the leftovers. Waterfall FIRST, then the headline.
      expect(presenter.waterfall.pluck(:funded)).to eq([500, 200, 0])
      expect(presenter.available).to eq(700)
      expect(presenter.waterfall.pluck(:funded)).to eq([500, 200, 0])
    end
  end

  # Separate from the block above because that one's `before` fixes three distinct priorities, which
  # is exactly the shape that cannot see a tie-break at all.
  describe "#waterfall priority ties" do
    it "breaks a tie by name so the same data funds the same category every load", :aggregate_failures do
      # Written in reverse alphabetical order on purpose: `Category.in_fill_order` orders
      # `[priority, name]`, and a sort on priority alone would fund Zoo first for no reason the user
      # can see — random UUID bytes deciding where the money goes.
      rate(holder("Zoo", priority: 1), 300)
      rate(holder("Apples", priority: 1), 300)
      income(300)

      rows = presenter.waterfall

      expect(rows.map { |r| r[:category].name }).to eq(["Apples", "Zoo"])
      # Keyed by name rather than by row index: the tie is not cosmetic, it decides which category
      # the money actually reaches, and a positional assertion would hold with the two swapped.
      expect(rows.to_h { |r| [r[:category].name, r[:funded]] }).to eq("Apples" => 300, "Zoo" => 0)
    end
  end

  describe "#waterfall with a root in the red" do
    # `remaining.clamp(0.to_d, needed)` is the guard: with `remaining` negative the clamp returns the
    # zero LOW bound rather than raising, which is what keeps a user whose root is overdrawn — the
    # user most in need of reading this screen — off a 500.
    it "funds nothing and still states every ask", :aggregate_failures do
      income(100)
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 500)
      rate(holder("Rent", priority: 1), 300)

      rows = presenter.waterfall

      expect(presenter.available).to eq(-400)
      expect(rows.pluck(:funded)).to eq([0])
      expect(rows.pluck(:short)).to eq([300])
      expect(presenter.shortfall).to eq(300)
      expect(presenter).not_to be_covered
    end

    # A negative ask is reachable — `HoldingCalculator#goal_required` returns `[rate, remaining].min`
    # — and `clamp(0, negative)` raises ArgumentError, which on the ROOT route takes out the whole
    # app rather than one screen. Written through `update_column` past Budget's validation, exactly
    # as AllocationCalculator's own example does.
    it "floors a negative ask rather than raising on the clamp", :aggregate_failures do
      goal = savings_goal("Vacation", priority: 1, target: 1_200)
      rule = rate(goal, 150)
      rule.update_column(:amount, -150) # rubocop:disable Rails/SkipsModelValidations
      income(500)

      expect(presenter.waterfall).to be_empty
      expect(presenter.total_required).to eq(0)
    end
  end

  # A category that asks for nothing is not a row, and the reason is what it looked like on a screen:
  # "$0.00 of $0.00", below the red "ran out here" line, which reads as "this got nothing because the
  # money ran out" when the truth is "this needed nothing".
  describe "#waterfall with a category that asks for nothing" do
    it "leaves it out of the rows and out of the gap", :aggregate_failures do
      income(500)
      settled = holder("Rent", priority: 1)
      rate(settled, 300)
      allocate(settled, 300)
      rate(holder("Groceries", priority: 2), 400)

      expect(presenter.waterfall.map { |r| r[:category].name }).to eq(["Groceries"])
      expect(presenter.total_required).to eq(400)
      expect(presenter.available).to eq(200)
      expect(presenter.shortfall).to eq(200)
      expect(presenter.projected_buffer).to eq(0)
    end
  end

  describe "#cutoff" do
    # THE `accounts.one?` GATE IS DELETED (Task 6). It existed because each account drained its own
    # pot, so with several accounts there was no single moment the money ran out and the line was
    # suppressed outright. There is one root now, so the line is drawn whatever the user banks with —
    # which is what this example is about, and why it mints a second account it otherwise ignores.
    it "draws the line for a user with several accounts", :aggregate_failures do
      create(:pool, :account, user: user, name: "Ally")
      rate(holder("Rent", priority: 1), 500)
      rate(holder("Groceries", priority: 2), 400)
      income(500)

      expect(presenter.accounts.size).to eq(2)
      expect(presenter.cutoff).to eq(1)
    end

    it "is nil on a covered period, where the index would find nothing and point past the last row" do
      rate(holder("Rent", priority: 1), 100)
      income(500)

      expect(presenter.cutoff).to be_nil
    end
  end

  describe "#covered?" do
    it "is true when available meets the requirement", :aggregate_failures do
      rate(holder("Groceries", priority: 1), 100)
      income(500)

      expect(presenter).to be_covered
      expect(presenter.shortfall).to eq(0)
    end
  end

  describe "#overdrawn_accounts" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "names the accounts below zero and no others", :aggregate_failures do
      income(500)
      create(:pool_movement, from_pool: checking, to_pool: ally, amount: 900, date: today, kind: :transfer)

      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
      expect(presenter.overdraft_for(checking)).to eq(400)
    end

    it "is empty when every account is in the black" do
      income(10)

      expect(presenter.overdrawn_accounts).to be_empty
    end

    # THE WHOLE REASON THIS READER EXISTS, and the two-ledger version of it is sharper than the pool
    # era's: the purpose ledger can be perfectly in order while the BANK is overdrawn. Every dollar
    # of income was allocated, then the category was overspent — so available is $0, nothing is
    # short, and $500 of real debt renders nowhere unless a band asks for it by name.
    it "reports a debt no purpose-ledger figure contains", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 1_000)
      allocate(groceries, 1_000)
      spend(groceries, 1_500)

      expect(presenter.available).to eq(0)
      expect(presenter.balance_of(checking)).to eq(-500)
      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
    end

    # ── DELETED (Task 6): the assertion that an overdrawn account's `status_for` is `:overdrawn`.
    # `#status_for` takes a CATEGORY now, and an account has no rules to be on track with — a status
    # is a reading of what a holder holds against what fills it. The standing band prints the figure
    # directly, through `#overdraft_for`, instead of borrowing the row vocabulary.
  end

  describe "#projected_buffer" do
    it "is what stays unclaimed once every holder is funded", :aggregate_failures do
      income(500)
      rate(holder("Groceries", priority: 1), 100)

      expect(presenter).to be_covered
      expect(presenter.projected_buffer).to eq(400)
    end

    # WITH ONE ROOT THIS IS ZERO WHENEVER THE PERIOD IS SHORT, which is the simplification the
    # collapse bought and is worth pinning as an identity rather than as a literal: the two figures
    # the standing band prints now subtract to its own headline.
    it "is zero when the period is short, where the two figures agree", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.shortfall).to eq(presenter.total_required - presenter.available)
      expect(presenter.projected_buffer).to eq(0)
    end

    # ── DELETED (Task 6): "is the cash this period's pools cannot reach" and "counts only the surplus
    # of an account that funds pools of its own". Both planted money in an account whose own
    # envelopes were already funded and pinned that it could not close a gap somewhere else. Money is
    # not in an account on the purpose ledger at all (§2), so there is nothing left to strand.
  end

  describe "#attention_categories" do
    it "returns only categories whose status needs attention" do
      quiet = holder("Groceries", priority: 1)
      rate(quiet, 100)
      allocate(quiet, 100)

      bill(holder("Dentist", priority: 2), amount: 300, due: Date.new(2026, 2, 14))

      expect(presenter.attention_categories.map(&:name)).to eq(["Dentist"])
    end

    it "lists them by priority, then name" do
      # Created in the reverse of the expected order, so insertion order alone cannot produce the
      # answer: `Category.in_fill_order` is what puts them right.
      [["Zoo", 2], ["Apples", 2], ["Urgent", 1]].each do |name, priority|
        bill(holder(name, priority: priority), amount: 300, due: Date.new(2026, 2, 14))
      end

      expect(presenter.attention_categories.map(&:name)).to eq(["Urgent", "Apples", "Zoo"])
    end

    # ── DELETED (Task 6): an overdrawn ACCOUNT is no longer one of these, and it never was one of
    # these — it reached the attention band through `home/_attention`'s own `overdrawn_accounts`
    # term, which is gone. The fix beside a problem row is an ALLOCATION, and an allocation cannot
    # touch the physical ledger, so offering one against a bank overdraft would propose a mistake to
    # fix a problem it cannot reach. `#overdrawn_accounts` still reports the debt; only the button
    # went away.
  end

  describe "#fix_for" do
    # THE DESTINATION EVERY EXAMPLE HERE IS ABOUT: $300 due Feb 14, inside the current period
    # (Feb 6–19), with no boundary left between tomorrow and the due date — so it is :wont_make_it
    # and its funding gap is the whole $300.
    def dentist
      @dentist ||= holder("Dentist", priority: 2).tap do |category|
        bill(category, amount: 300, due: Date.new(2026, 2, 14))
      end
    end

    it "offers AVAILABLE first, because idle money costs nothing to move", :aggregate_failures do
      # Rent takes the whole root in the waterfall, so Dentist is genuinely short — and the $500 is
      # nonetheless sitting unclaimed RIGHT NOW, which is what the reallocation screen would show.
      rate(holder("Rent", priority: 1), 500)
      dentist
      income(500)

      fix = presenter.fix_for(dentist)

      expect(presenter.status_for(dentist).state).to eq(:wont_make_it)
      expect(fix.amount).to eq(300)
      expect(fix.source.name).to eq("Available")
      expect(fix.source.id).to eq("available")
    end

    # A CATEGORY IS A SOURCE, and the gate is `free_amount` — holding less what every rule holds —
    # rather than the balance the reallocation screen allows a USER to move against. Two thresholds
    # for two different acts: there the app STATES the damage, here the app is PROPOSING, so it must
    # not propose robbing a category that is counting on the money.
    it "falls through to a holder with free money when available has none", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      rate(rent, 500)
      allocate(rent, 800)
      dentist
      income(800)

      fix = presenter.fix_for(dentist)

      expect(presenter.available).to eq(0)
      expect(fix.source.name).to eq("Rent")
      expect(fix.candidate.damage.balance_before).to eq(800)
      expect(fix.candidate.damage.balance_after).to eq(500)
    end

    it "offers no source when nothing has that much spare", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      rate(rent, 500)
      allocate(rent, 500)
      dentist
      income(500)

      fix = presenter.fix_for(dentist)

      expect(fix.needs_money?).to be(true)
      expect(fix.source).to be_nil
      expect(fix.candidate).to be_nil
    end

    # A category that is itself behind is not a source: proposing to rob it is not a fix.
    it "refuses a source whose own status needs attention", :aggregate_failures do
      troubled = holder("Car Insurance", priority: 1)
      bill(troubled, amount: 900, due: Date.new(2026, 2, 14))
      allocate(troubled, 400)
      dentist
      income(400)

      expect(presenter.status_for(troubled).needs_attention?).to be(true)
      expect(presenter.fix_candidates_for(dentist)).to be_empty
    end

    # THE NEXT DISTRIBUTION ALREADY SOLVES THIS, so the band does not talk the user into a move they
    # do not need to make. Read off the SAME waterfall the band below renders, so the two cannot
    # contradict each other in two adjacent inches of one screen.
    it "says the money is coming when the waterfall funds the whole ask", :aggregate_failures do
      dentist
      income(500)

      fix = presenter.fix_for(dentist)

      expect(presenter.waterfall.map { |r| [r[:category].name, r[:short]] }).to eq([["Dentist", 0]])
      expect(fix).to be_covered
      expect(fix.source).to be_nil
    end

    # RULING 4, and the one state where #funding_gap and #amount part company: an overdue bill whose
    # category holds every penny of it needs PAYING, not funding. `#amount` there is the bill's
    # unpaid remainder, and offering to move it in would leave the category holding double.
    # `#payable` gives the rule an ITEM, because that is the app's only signal that a bill was PAID —
    # `BudgetCalculator#fulfilled?` reads `today >= anchor_date` for an item-less one-time rule, so
    # such a rule can never be overdue at all.
    #
    # The two figures part company here and nowhere else: the ROW prints the bill's unpaid
    # remainder, and the ACTION would close nothing at all.
    it "asks for nothing on an overdue bill the category already holds the money for", :aggregate_failures do
      insurance = payable("Renters Insurance", amount: 180, due: Date.new(2026, 2, 1))
      income(500)
      allocate(insurance, 180, on: Date.new(2026, 1, 20))

      fix = presenter.fix_for(insurance)

      expect(presenter.status_for(insurance).state).to eq(:overdue)
      expect(presenter.status_for(insurance).amount).to be_positive
      expect(fix.amount).to eq(0)
      expect(fix.needs_money?).to be(false)
    end

    # ── DELETED (Task 6): "answers nil outright for a pool with no account". `#fix_for` returned nil
    # for an orphan because no account's money could reach it and `PoolStatus#amount` would have
    # named the pool's own BALANCE as the size of its problem. There is no orphan.

    it "rounds the amount so the button, the link and the preview name one figure", :aggregate_failures do
      car = holder("Car Insurance", priority: 1)
      create(:budget, pool: nil, category: car, amount: 7_200, interval_months: 12, anchor_date: Date.new(2026, 8, 1))
      income(1)

      fix = presenter.fix_for(car)

      expect(fix.amount).to eq(fix.amount.round(2))
      expect(fix.amount_param).to eq(format("%.2f", fix.amount))
    end
  end

  describe "#structurally_underwater?" do
    it "is true when the rules need more than typical income" do
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).to be_structurally_underwater
    end

    it "is false when they fit" do
      rate(holder("Rent", priority: 1), 500)

      expect(presenter).not_to be_structurally_underwater
    end

    # The boundary the `>` sits on. Rules that consume the declared income exactly are not a
    # structural problem — there is nothing reallocation could not still fix — so this must not fire.
    it "is false when the rules land exactly on typical income", :aggregate_failures do
      rate(holder("Rent", priority: 1), 2_400)

      expect(presenter.total_required).to eq(user.typical_income)
      expect(presenter).not_to be_structurally_underwater
    end

    it "is false when typical income is unset" do
      user.update!(typical_income: nil)
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).not_to be_structurally_underwater
    end

    # THE OTHER HALF OF THE DECLARATION. Income with a blank cadence is reachable — the Budget page's
    # form offers "Not set" and clearing the period deliberately keeps the income — and in that state
    # `Budget.steady_need` falls back to treating a period as a calendar month. A per-rule normaliser
    # may fall back; a VERDICT may not.
    it "is false when income is declared but no cadence is", :aggregate_failures do
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).to be_structurally_underwater

      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(described_class.new(user: user, today: today)).not_to be_structurally_underwater
    end

    # THE MEMO, asserted by counting the sum rather than by trusting the spelling. `false` is the
    # case that needs the assertion: a `||=` memo re-runs its body every time the answer is falsey,
    # so the memo would be silently absent for exactly the population it was written for.
    it "computes the sum once for a budget that does not fit" do
      rate(holder("Rent", priority: 1), 3_000)
      allow(Budget).to receive(:steady_need).and_call_original

      3.times { presenter.structurally_underwater? }

      expect(Budget).to have_received(:steady_need).once
    end

    it "computes the sum once for a budget that does fit" do
      rate(holder("Rent", priority: 1), 500)
      allow(Budget).to receive(:steady_need).and_call_original

      3.times { presenter.structurally_underwater? }

      expect(Budget).to have_received(:steady_need).once
    end

    # THE CASE THE OLD READER GOT WRONG. `total_required` is THIS period's ask, catch-up included: a
    # $5,200 annual premium falling due inside the current period asks for all $5,200 now, so it
    # clears the declared $2,400 twice over and the band said "your budget doesn't fit your income"
    # at a user whose rules cost $200 a period.
    it "is false in a catch-up period whose rules still fit the income", :aggregate_failures do
      annual(holder("Car Insurance", priority: 1), amount: 5_200, due: today + 3.days)

      expect(presenter.total_required).to be > user.typical_income
      expect(Budget.steady_need(user, today: today)).to eq(200)
      expect(presenter).not_to be_structurally_underwater
    end

    # The other half of the divergence, and the dangerous one: a period in which everything has
    # already been funded asks for nothing, so the old reader read $0 against $2,400 and stayed
    # silent on a budget that cannot be made to work at any distribution.
    it "is true on a fully funded period whose rules do not fit", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      rate(rent, 3_000)
      allocate(rent, 3_000)

      expect(presenter.total_required).to eq(0)
      expect(presenter).to be_structurally_underwater
    end
  end
end
