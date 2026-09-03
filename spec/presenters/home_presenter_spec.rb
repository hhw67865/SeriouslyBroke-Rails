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
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
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
  # asked for. A rule belongs to the thing that holds the money now — the budget factory's owner
  # is a funded category (two-ledger spec §3).
  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount)
  end

  def bill(category, amount:, due:)
    create(:budget, :one_time, category: category, amount: amount, anchor_date: due)
  end

  # A rule that rolls: its due date moves with the cycles that have gone by, which is what makes it
  # depend on which day the calculator is asked about.
  def rolling(category, amount:, anchor:)
    create(:budget, category: category, amount: amount, interval_months: 1, anchor_date: anchor)
  end

  # INCOME RAISES BOTH LEDGERS AT ONCE (§2): the pot, and available. It lands in the user's main
  # account, which is the only place income may land.
  def income(amount, on: today)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # SPENDING LOWERS THE POT ALWAYS, and lowers the CATEGORY when the category counts that day —
  # otherwise it lowers available (§4's start-date rule).
  def spend(category, amount, on: today)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A BILL THAT ROLLS ONCE A YEAR: its whole face value falls due inside the current period, which
  # is what makes `remaining_plan` and `Budget.steady_need` diverge.
  def annual(category, amount:, due:)
    create(:budget, category: category, amount: amount, interval_months: 12, anchor_date: due)
  end

  # A DATED BILL THE USER ACTUALLY PAYS: an item is the only fulfilment signal BudgetCalculator
  # accepts, and therefore the only way a rule can be overdue rather than merely settled by its date.
  def payable(name, amount:, due:, priority: 1)
    holder(name, priority: priority).tap do |category|
      item = create(:item, category: category, name: "#{name} Bill")
      create(:budget, :one_time, category: category, item: item, amount: amount, anchor_date: due)
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
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

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
      create(:category, :income, user: user, name: "Salary")

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

  # ── RENAMED (answers-first Task 1): this was `describe "#total_required"`, and every example in
  # it is carried unchanged. The reader did not change and must not — Home's word for the figure
  # did ("spoken for"), and two names for one sum is exactly the drift the one-spelling rule
  # (answers-first spec §3) is written against. `#total_required` no longer exists.
  describe "#remaining_plan" do
    it "sums what every holder needs this period" do
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Gas", priority: 2), 80)

      expect(presenter.remaining_plan).to eq(480)
    end

    it "counts savings goals alongside spending categories", :aggregate_failures do
      rate(holder("Groceries", priority: 1), 400)
      rate(savings_goal("Vacation", priority: 2), 150)

      expect(presenter.remaining_plan).to eq(550)
      expect(presenter.waterfall.map { |r| r[:category].name }).to eq(["Groceries", "Vacation"])
    end

    it "is a decimal zero, not an integer, for a user with no categories", :aggregate_failures do
      expect(presenter.remaining_plan).to eq(0)
      expect(presenter.remaining_plan).to be_a(BigDecimal)
      expect(presenter.shortfall).to be_a(BigDecimal)
    end

    # ** THE ONE-SPELLING EXAMPLE (answers-first spec §3, the plan's binding constraint). ** The
    # figure `free_to_spend` subtracts is read through BOTH entry points on ONE fixture: this
    # presenter, and the waterfall the Distribute screen actually renders. They are the same sum of
    # the same per-row `needed` — `HoldingCalculator#required` on AllocationCalculator's
    # net-of-sweep calculator — and the only way this example can fail is if somebody writes a
    # second period-ask arithmetic on Home.
    #
    # THE FIXTURE IS DELIBERATELY MIXED, because a flat pair of rate rules would agree under almost
    # any re-derivation: a partly-allocated envelope (`#required` nets the allocation off), a dated
    # bill (catch-up, not a steady rate) and a savings goal (`goal_required`'s `min(rate,
    # remaining)`) each exercise a different arm of the ask.
    #
    # NOT `Budget.steady_need`, which is the Budget page's STRUCTURAL check and is deliberately a
    # different question — see `#structurally_underwater?` below, where the two diverge in both
    # directions on the same budget.
    #
    # ** THE ALLOCATION IS DATED INTO THE PREVIOUS PERIOD, AND IT HAS TO BE. ** Measured while
    # writing this: with the $100 dated `today` the two entry points disagreed by exactly that $100,
    # and the disagreement is CORRECT rather than a drift. `DistributionPresenter` describes what
    # re-running THIS period's distribution would do, so it deletes this period's allocation rows
    # and re-derives against a world without them (see its #snapshot); Home describes what is still
    # owed given what has already been given. Two screens, two questions — and comparing them
    # requires a fixture with no distribution inside the window, or the example would be pinning the
    # delete-and-rollback rather than the ask. A DATED bill is what lets the fixture keep its
    # part-funded arm anyway: it holds its $100 across the boundary because a category with no rate
    # rule never sweeps (`HoldingCalculator#compute_period_closed`).
    it "is the same figure the distribute waterfall asks for", :aggregate_failures do
      income(1_000)
      rate(holder("Groceries", priority: 1), 400)
      dentist = payable("Dentist", amount: 300, due: Date.new(2026, 2, 14), priority: 2)
      allocate(dentist, 100, on: Date.new(2026, 1, 17))
      rate(savings_goal("Vacation", priority: 3, target: 1_200), 150)

      waterfall_ask = DistributionPresenter.new(user: user, today: today).lines.sum(0.to_d, &:needed)

      # Planted, so the example fails loudly if the fixture stops exercising all three arms rather
      # than merely agreeing with itself: the whole $400 rate, $200 of the part-funded bill, $150 of
      # the goal's own rate.
      expect(presenter.remaining_plan).to eq(750)
      expect(presenter.remaining_plan).to eq(waterfall_ask)
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

      expect(rows[0].short).to eq(0)
      expect(rows[1].short).to eq(200)
      expect(rows[2].short).to eq(150)
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
      #
      # `.short` RATHER THAN `[:short]` (Task 7): the rows are `AllocationCalculator::Row` structs
      # now, and `short` is a METHOD (`needed - funded`) rather than a member — `Struct#[]` raises
      # `no member 'short' in struct`. `[:needed]` and `[:funded]` are members and still answer.
      expect(rows.map { |r| r[:needed] - r[:funded] }).to eq(rows.map(&:short))
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
      expect(rows.map(&:short)).to eq([300])
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
      expect(presenter.remaining_plan).to eq(0)
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
      expect(presenter.remaining_plan).to eq(400)
      expect(presenter.available).to eq(200)
      expect(presenter.shortfall).to eq(200)
      # WAS `projected_buffer.to eq(0)` (answers-first Task 1). That reader clamped itself to the
      # money actually handed out, so a short period always read $0 — which is what made it a poor
      # headline. `free_to_spend` subtracts what the plan still ASKS for, so the same fixture states
      # the $200 gap instead of hiding it: $200 available less a $400 ask, capped at the $500 pot.
      expect(presenter.free_to_spend).to eq(-200)
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
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 900, date: today, kind: :transfer)

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

  # ── DELETED (answers-first Task 1): the whole `#projected_buffer` describe, four examples.
  #
  #   * "is what stays unclaimed once every holder is funded"
  #   * "is zero when the period is short, where the two figures agree"
  #   * "is negative exactly when the root is, which a covered period reaches"
  #   * "cannot go below zero while the root is in the black"
  #
  # THE READER IS GONE AND SO IS THE SENTENCE IT EXISTED FOR. `projected_buffer` was `available − Σ
  # FUNDED`, so it clamped itself to what the waterfall actually handed out and read $0 on every
  # short period — which is why the last two examples above are about its SIGN rather than about a
  # figure. `free_to_spend` subtracts what the plan still ASKS for (`Σ needed`), so it states the
  # gap those examples had to describe in the negative, and the two archetypes below are their
  # successors: "states the gap rather than reporting nothing left" carries the short period, and
  # "is negative for a period whose spending has drained the root" carries the covered-with-a-
  # deficit fixture the MED-1 review measured. The word "unclaimed" dies with the reader
  # (answers-first spec §3).

  # ── THE HERO CARD'S FOUR READERS (answers-first spec §§2-3) ──────────────────────────────────

  describe "#in_checking" do
    # THE NUMBER THE BANK APP SHOWS, and it is `AccountLedger#pot` rather than a sum of accounts:
    # only main carries the entry side of the physical ledger (§2), so a second account's money is
    # not in checking however much of it there is.
    it "is the pot, not the user's money everywhere", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(400)
      expect(presenter.balance_of(ally)).to eq(600)
    end

    it "is a decimal zero for a user whose account holds nothing", :aggregate_failures do
      expect(presenter.in_checking).to eq(0)
      expect(presenter.in_checking).to be_a(BigDecimal)
    end
  end

  describe "#free_to_spend" do
    # ARCHETYPE 1 (spec §9): the fresh user. Nothing in, nothing planned — and the card still
    # renders, so every figure on it has to be a real zero rather than a nil the view guards.
    it "is a decimal zero all the way down for a fresh user", :aggregate_failures do
      expect(presenter.free_to_spend).to eq(0)
      expect(presenter.free_to_spend).to eq(presenter.in_checking)
      expect(presenter.free_to_spend).to be_a(BigDecimal)
      expect(presenter).not_to be_free_cap_bound
    end

    # ARCHETYPE 2, FIRST DIRECTION (spec §9): the `min` chooses the SUBTRACTION. Planted both ways
    # round — $2,000 in, $400 still asked for, so $1,600 is free and the pot is nowhere near
    # binding.
    it "is available less the remaining plan when the money is all in checking", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.in_checking).to eq(2_000)
      expect(presenter.available).to eq(2_000)
      expect(presenter.remaining_plan).to eq(400)
      expect(presenter.free_to_spend).to eq(1_600)
      expect(presenter).not_to be_free_cap_bound
    end

    # ARCHETYPE 2, SECOND DIRECTION: the `min` chooses the POT, which is the ruled cap (spec §3) —
    # money you would have to move out of savings first is not free in the moment. THE SAME FIXTURE
    # as above with $1,500 walked over to Ally: the purpose ledger has not moved at all (an account
    # movement allocates nothing), so `available − remaining_plan` is still $1,600 and only the cap
    # brings the answer down. A reader that had quietly dropped the `min` would still read $1,600
    # here, which is what makes this the example that catches it.
    it "is capped at the pot when the unspoken-for money is parked elsewhere", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(500)
      expect(presenter.available - presenter.remaining_plan).to eq(1_600)
      expect(presenter.free_to_spend).to eq(500)
      expect(presenter).to be_free_cap_bound
    end

    # ARCHETYPE 3 (spec §9): free below zero, NEVER clamped. $150 in against a $400 rule — the plan
    # asks for $250 more than exists, and the card has to say so.
    it "states the gap rather than reporting nothing left", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.free_to_spend).to eq(-250)
      expect(presenter).not_to be_free_cap_bound
    end

    # THE FIXTURE THE OLD BAND GOT WRONG (fix round 1 — MED-1), re-asked of the reader that
    # replaces it. No holder categories at all, so nothing is short and `#covered?` is trivially
    # true, while $100 of unbudgeted spending has drained the root. `projected_buffer` called that
    # "-$100.00 still unclaimed"; free simply says -$100.00 is free, which is the honest sentence.
    it "is negative for a period whose spending has drained the root", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 100)

      expect(presenter).to be_covered
      expect(presenter.remaining_plan).to eq(0)
      expect(presenter.free_to_spend).to eq(-100)
    end

    # ARCHETYPE 4 (spec §9): the physical overdraft. The pot is the smaller of the two here as well,
    # so the cap is NOT what makes this negative — every dollar of income was allocated and then
    # overspent. Both figures are pinned because the card colours them separately.
    it "is negative beside a negative pot", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 1_000)
      allocate(groceries, 1_000)
      spend(groceries, 1_500)

      expect(presenter.in_checking).to eq(-500)
      expect(presenter.available).to eq(0)
      expect(presenter.remaining_plan).to eq(1_000)
      expect(presenter.free_to_spend).to eq(-1_000)
    end
  end

  # ** WHICH KIND OF NEGATIVE (fix round 1 — MED-1). ** `#free_to_spend` goes below zero for two
  # unrelated reasons and the card was telling both of them the same story. The three examples below
  # are the three combinations that exist, and the third is the one that makes this a separate
  # predicate rather than a synonym for `#free_cap_bound?`.
  describe "#plan_outruns_the_money?" do
    # THE REVIEWER'S MEASURED FIXTURE. $1,000 of income, $1,200 walked over to a savings account,
    # and NOT ONE RULE — so the pot is -$200 while $1,000 is unspoken for. Nothing is set aside,
    # nothing is spoken for, and the money is one transfer away: every part of "more is set aside or
    # spoken for than you have" and "nothing is free until money comes in" was false here.
    it "is false when the money is simply in another account", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_200, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(-200)
      expect(presenter.available).to eq(1_000)
      expect(presenter.remaining_plan).to eq(0)
      expect(presenter.free_to_spend).to eq(-200)
      expect(presenter).to be_free_cap_bound
      expect(presenter).not_to be_plan_outruns_the_money
    end

    # THE OTHER DIRECTION on the same fixture shape: $150 in, $300 spent with no rules to hold it,
    # and a $400 rule still asking. The root is -$150 and the plan wants $400 more, so there is
    # genuinely nothing anywhere — and the cap is NOT what made free negative.
    it "is true when every account together is short of the plan", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 300)

      expect(presenter.in_checking).to eq(-150)
      expect(presenter.free_to_spend).to eq(-550)
      expect(presenter).not_to be_free_cap_bound
      expect(presenter).to be_plan_outruns_the_money
    end

    # ** THE COMBINATION THAT FORBIDS SPELLING THIS AS `#free_cap_bound?`. ** A pot of -$500 against
    # an unspoken-for -$100 is cap-bound AND genuinely out of money: $1,000 in, $1,500 moved to
    # savings, and $1,100 of rules still asking. Both predicates are true, they are answering
    # different questions, and a card that had used the cap as a proxy for the cause would print the
    # money-is-elsewhere sentence at a user whose budget does not fit.
    it "is true even where the cap binds, because they are different questions", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      rate(holder("Groceries", priority: 1), 1_100)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(-500)
      expect(presenter.available - presenter.remaining_plan).to eq(-100)
      expect(presenter).to be_free_cap_bound
      expect(presenter).to be_plan_outruns_the_money
    end

    it "is false for a fresh user, whose plan asks for nothing at all" do
      expect(presenter).not_to be_plan_outruns_the_money
    end
  end

  describe "#free_cap_bound?" do
    # THE BOUNDARY THE `<` SITS ON. Money exactly equal to what the pot holds is not "parked
    # somewhere else", so the subline must not fire: $1,000 in checking against $1,000 of
    # unspoken-for money is one pile, and the card would be inventing a second.
    it "is false when the two sides of the min are equal", :aggregate_failures do
      income(1_000)

      expect(presenter.free_to_spend).to eq(1_000)
      expect(presenter).not_to be_free_cap_bound
    end
  end

  describe "#period_progress" do
    # DAY X OF Y OFF `#period_range`, which is `User#period_containing` — the one window every
    # other screen reads. `today` is the presenter's, planted, so nothing here depends on the day
    # the suite runs (CLAUDE.md's third flake cause).
    it "counts today into the declared period", :aggregate_failures do
      progress = described_class.new(user: user, today: Date.new(2026, 2, 12)).period_progress

      expect([progress.first, progress.last]).to eq([Date.new(2026, 2, 6), Date.new(2026, 2, 19)])
      expect([progress.day, progress.days]).to eq([7, 14])
      expect(progress.days_left).to eq(7)
      expect(progress.percent).to eq(50)
    end

    # THE FIRST DAY AND THE LAST, so the fraction cannot be off by one at either end: day 1 of 14 is
    # not zero elapsed periods of progress, and the closing day is full rather than one short.
    it "runs from the opening day to the closing one", :aggregate_failures do
      opening = described_class.new(user: user, today: Date.new(2026, 2, 6)).period_progress
      closing = described_class.new(user: user, today: Date.new(2026, 2, 19)).period_progress

      expect([opening.day, opening.days_left, opening.percent]).to eq([1, 13, 7])
      expect([closing.day, closing.days_left, closing.percent]).to eq([14, 0, 100])
    end

    # Nil for a user who has declared no period, the same gate `#period_range` already applies:
    # `User#period_containing` falls back to the calendar month, which is right for a normaliser and
    # a lie on a card that would print a boundary nobody set.
    it "is nil before a period is declared" do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(presenter.period_progress).to be_nil
    end
  end

  # THE HERO ADDS NO QUERY TO A SCREEN THAT HAS ALREADY DRAWN ITS ACCOUNTS AND ITS WATERFALL, which
  # is the whole claim behind composing it out of readers the presenter already memoises: `pot` is
  # `#balance_of` on the ledger the accounts band builds, and `remaining_plan` is a sum over the
  # rows the attention band already holds. The house idiom (distribution_clock_spec,
  # ledger_sharing_spec) — schema and transaction chatter excluded.
  describe "the hero's query cost" do
    def count_statements(&block)
      statements = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      statements
    end

    def read_the_hero
      presenter.in_checking
      presenter.remaining_plan
      presenter.free_to_spend
      presenter.free_cap_bound?
      presenter.period_progress
    end

    # TWO STATEMENTS AND THEN NONE, and the shape of the pair is the whole point.
    #
    # THE TWO ARE `AccountLedger#entry_side`'s income and expense SUMs — the pot's own term, which
    # that class does not memoise (its movement totals it does, and the warm-up above pays those).
    # MEASURED, NOT REASONED ABOUT: this read SIX before `#in_checking` was memoised, because the
    # card asks for the pot three times over — the figure, the `min`, and the cap predicate — and
    # each ask ran both sums again.
    #
    # THE SECOND COUNT IS THE ONE THAT PINS THE DESIGN: every figure on this card is composed from
    # readers the presenter already holds, so once anything has been read, reading all of it costs
    # nothing. A reader added here that opened a ledger of its own would fail this and not the first.
    it "costs two statements for the pot and nothing at all thereafter", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)
      presenter.accounts.each { |account| presenter.balance_of(account) }
      presenter.waterfall
      presenter.available

      expect(count_statements { read_the_hero }).to eq(2)
      expect(count_statements { read_the_hero }).to eq(0)
    end
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

  # ── "THIS PERIOD" (answers-first spec §4) ──────────────────────────────────────────────────────
  #
  # The bars themselves are pinned in `spec/system/home/this_period_spec.rb`, on the screen. What is
  # here is what a browser cannot reach cheaply: the WINDOW both directions, the partition between a
  # budgeted row and an unbudgeted one, and the sort key.
  describe "#period_rows" do
    # THE WINDOW, BOTH DIRECTIONS, ON ONE CATEGORY. The period containing Feb 6 on a biweekly cadence
    # anchored Feb 6 is Feb 6–19, so the Feb 10 receipt is inside it and the Feb 2 one is not — while
    # BOTH drain the category's holding, which is exactly why "spent this period" cannot be read off
    # `HoldingCalculator#balance`.
    it "counts the spending inside this period and no other", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      allocate(groceries, 400)
      spend(groceries, 310, on: Date.new(2026, 2, 10))
      spend(groceries, 50, on: Date.new(2026, 2, 2))

      row = presenter.period_rows.sole

      expect(row.spent).to eq(310)
      expect(row.planned).to eq(400)
      # The cumulative reading, asserted absent — and asserted to be genuinely different on this
      # fixture, so the first expectation is pinning the window rather than passing by coincidence.
      expect(groceries.holding_calculator(today: today).balance).to eq(40)
    end

    # THE PLAN IS THE PER-PERIOD NORMALISER, not the sticker price: `Budget#steady_ask` turns a
    # $600-a-month rule into $276.92 of a biweekly period (26 periods a year against 12 months), and
    # a bar denominated in the monthly figure would draw a full envelope as under half of one.
    # Pinned to the literal, so a denominator that reverted to `amount` fails rather than agreeing
    # with whatever the normaliser happens to return.
    it "denominates a monthly rule in what it claims from one period", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      create(:budget, category: rent, amount: 600, interval_months: 1, anchor_date: Date.new(2026, 3, 1))

      expect(presenter.period_rows.sole.planned).to eq(276.92)
      expect(presenter.period_rows.sole.planned).not_to eq(600)
    end

    # A GOAL MEASURES AGAINST ITS TARGET (spec §4: "savings goals keep their target bars"), and
    # #filled is its HOLDING rather than its spending — which is what keeps the row from reading as
    # money to spend.
    it "measures a goal against its target and fills the bar with what it holds", :aggregate_failures do
      goal = savings_goal("Vacation", priority: 1, target: 2_400)
      allocate(goal, 424)

      row = presenter.period_rows.sole

      expect(row).to be_goal
      expect(row.planned).to eq(2_400)
      expect(row.filled).to eq(424)
      expect(row.percent).to eq(18)
    end

    # TROUBLE FIRST, THEN FILL ORDER. Three categories in fill order 1-2-3 with the LAST in trouble:
    # both halves are asserted at once, because either alone passes against a list that was simply
    # reversed.
    it "sorts trouble first and keeps fill order behind it" do
      rate(holder("Rent", priority: 1), 400)
      rate(holder("Groceries", priority: 2), 400)
      spend(holder("Dining Out", priority: 3), 80)

      expect(presenter.period_rows.map { |row| row.category.name }).to eq(["Dining Out", "Rent", "Groceries"])
    end
  end

  describe "#unbudgeted_rows" do
    # ZERO-SPEND ROWS ARE ABSENT BY CONSTRUCTION — they never appear in the grouped sum — which is
    # the rule stated as a query rather than as a filter somebody could forget.
    it "lists only the unbudgeted categories with spending in this period", :aggregate_failures do
      spender = create(:category, :expense, user: user, name: "Subscriptions")
      create(:entry, item: create(:item, category: spender), amount: 32, date: today)
      create(:category, :expense, user: user, name: "Someday")
      stale = create(:category, :expense, user: user, name: "Old")
      create(:entry, item: create(:item, category: stale), amount: 99, date: Date.new(2026, 2, 2))

      expect(presenter.unbudgeted_rows.map { |row| row.category.name }).to eq(["Subscriptions"])
      expect(presenter.unbudgeted_rows.sole.spent).to eq(32)
    end

    # ** THE PARTITION'S ONE HARD EDGE. ** A category funded PART-WAY THROUGH this period drains
    # available for the receipts dated before its `funded_since` and itself for the ones after — so
    # the same category appears on both sides of `ENTRY_CATEGORY_ID`. It belongs in the budgeted list
    # with its bar, once; its pre-funding spending is available's, which the hero's figures carry.
    it "never lists a budgeted category as unbudgeted as well", :aggregate_failures do
      groceries = holder("Groceries", priority: 1, funded_since: Date.new(2026, 2, 8))
      rate(groceries, 400)
      spend(groceries, 20, on: Date.new(2026, 2, 7))
      spend(groceries, 30, on: Date.new(2026, 2, 9))

      expect(presenter.unbudgeted_rows).to be_empty
      # And the bar counts only what the category itself drained, on the ledger's own rule.
      expect(presenter.period_rows.sole.spent).to eq(30)
    end
  end

  describe "#troubles" do
    # EACH KIND FROM AN EXISTING READER, and the list is what the strip renders from — so a trigger
    # added to the presenter and forgotten in the view, or the reverse, shows up here as a count.
    it "types each trigger and orders them money-gone-first", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: today, kind: :transfer)
      income(1_000)
      bill(holder("Dentist", priority: 1), amount: 300, due: Date.new(2026, 2, 14))

      expect(presenter.troubles.map(&:kind)).to eq([:overdraft, :category, :undistributed])
      expect(presenter.troubles.first.subject).to eq(ally)
      expect(presenter.troubles.second.subject.name).to eq("Dentist")
      expect(presenter).to be_trouble
    end

    # MAIN'S OVERDRAFT IS THE HERO'S RED FIGURE, so the strip must not repeat it: printing the same
    # debt twice with two different sentences about what counts it is worse than printing it once.
    it "leaves main's own overdraft out of the list", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Overspend"), 400)

      expect(presenter.in_checking).to eq(-400)
      expect(presenter.troubles.map(&:kind)).to eq([])
      expect(presenter).not_to be_trouble
    end

    # A USER WITH NOTHING TO DISTRIBUTE IS NOT IN TROUBLE. Every fresh account has an undistributed
    # period by definition, and a strip that fired on it would greet every new user with a demand
    # they cannot act on.
    it "asks nothing of a user whose rules ask for nothing", :aggregate_failures do
      income(1_000)

      expect(presenter.waterfall).to be_empty
      expect(presenter).not_to be_undistributed_period
      expect(presenter).not_to be_trouble
    end

    # THE OTHER DIRECTION OF THE SAME TRIGGER: one `Allocation.distributed` row inside the window and
    # the clock reports the period handed out. Read through `DistributionClock` rather than a second
    # `Allocation.distributed` query of this class's own.
    it "falls silent on the distribute trigger once this period has been distributed", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      allocate(groceries, 400)

      expect(presenter.waterfall).to be_empty
      expect(DistributionClock.new(user: user, today: today)).to be_distributed_this_period
    end
  end

  # ── THE ACCOUNTS LINE (answers-first spec §6) ──────────────────────────────────────────────────
  describe "#other_accounts" do
    # MAIN IS OUT OF THE FIGURE because its balance IS the hero's "In Checking" number; an onboarding
    # account is out because its card renders top-level, and a figure in the line for a card sitting
    # above it reads as two accounts.
    it "totals the finished accounts that are not main", :aggregate_failures do
      create(:category, :expense, user: user, name: "Opening Balance")
      income(1_000)
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 400, date: today, kind: :transfer)
      create(:pool, :account, user: user, name: "Fresh")

      expect(presenter.other_accounts).to eq([ally])
      expect(presenter.other_accounts_total).to eq(400)
      expect(presenter.onboarding_accounts.map(&:name)).to eq(["Fresh"])
      expect(presenter.collapsed_accounts).to eq([ally, checking])
    end
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

      expect(presenter.waterfall.map { |r| [r.category.name, r.short] }).to eq([["Dentist", 0]])
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
      create(:budget, category: car, amount: 7_200, interval_months: 12, anchor_date: Date.new(2026, 8, 1))
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

      expect(presenter.remaining_plan).to eq(user.typical_income)
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

    # THE CASE THE OLD READER GOT WRONG. `remaining_plan` is THIS period's ask, catch-up included: a
    # $5,200 annual premium falling due inside the current period asks for all $5,200 now, so it
    # clears the declared $2,400 twice over and the band said "your budget doesn't fit your income"
    # at a user whose rules cost $200 a period.
    it "is false in a catch-up period whose rules still fit the income", :aggregate_failures do
      annual(holder("Car Insurance", priority: 1), amount: 5_200, due: today + 3.days)

      expect(presenter.remaining_plan).to be > user.typical_income
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

      expect(presenter.remaining_plan).to eq(0)
      expect(presenter).to be_structurally_underwater
    end
  end
end
