# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Attention", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def envelope(name, amount, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_period_rate, pool: pool, amount: amount)
    pool
  end

  # MAIN-ACCOUNT SPEC §6: an income category may only point at the user's main account, so the
  # category here is always Checking's, never `into`'s. The money still ends up in `into` — the
  # entry lands in Checking and a `transfer` PoolMovement carries the same amount on to `into`,
  # exactly the write Task 3's routing feature automates for a real "deposit into another
  # account" choice. Checking's own balance nets to unchanged (income in, movement out); `into`
  # gains exactly what it always gained.
  def deposit(amount, into: checking)
    category = create(:category, :income, user: user, pool: checking)
    entry = create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    return entry if into == checking

    create(:pool_movement, from_pool: checking, to_pool: into, amount: amount, date: Date.current, source_entry: entry)
    entry
  end

  # `#orphan` AND `#quiet_orphan` ARE DELETED WITH THE SHAPE THEY BUILT (plan 3, task 6). Both
  # planted `create(:pool, user: user, ...)` with no account, and their comments said why it was
  # the ordinary case: "savings pools stay this way until Plan 3's backfill". The backfill has
  # landed — `Pool#account_matches_pool_type` requires an account for every envelope and goal and
  # `CHECK ((pool_type = 0) = (account_id IS NULL))` requires it again past the model — so no user
  # can be in that state and no fixture can put one there. `#orphan_section` goes with them.
  #
  # FIVE EXAMPLES DELETED BELOW, each named where it stood. `HomePresenter#orphan_pools`, the
  # attention band's orphan term and `home/_orphans` are KEPT and now select nothing; deleting the
  # orphan apparatus is the follow-up this tightening creates, named in `Pool::REFUSALS` and in the
  # task 6 report.

  def attention_section = find("section[aria-labelledby='attention-heading']")

  def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

  it "lists a pool that can't be funded in time", :aggregate_failures do
    dentist = create(:pool, :budget_pool, user: user, account: checking, name: "Dentist", priority: 1)
    create(:pool_budget, :one_time, pool: dentist, amount: 300, anchor_date: Date.current + 3.days)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Dentist")
      expect(page).to have_content("won't make it")
      expect(page).to have_content("1 thing needs you")
      expect(page).to have_no_content("Nothing needs you")
    end
  end

  it "says nothing needs you when every pool is quiet", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    # The money has to arrive before it can be moved. Without this deposit the movement
    # below leaves Checking at -$400 and the fixture is not quiet at all — see the
    # overdrawn example, which is that same fixture kept deliberately.
    deposit(400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing needs you")
      expect(page).to have_no_content("Groceries")
      expect(page).to have_no_content("overdrawn")
    end
  end

  it "shows no waterfall when there is no gap to explain", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_content("Nothing needs you")
    expect(page).to have_no_content("Where your money goes")
    expect(page).to have_no_content("ran out here")
  end

  # Seen on the screen: `won't make it · Aug 18` sat under "You're covered this period" with
  # the waterfall hidden, because the waterfall only rendered when short. PoolStatus describes
  # the pool NOW; the waterfall describes the plan. Showing the warning while suppressing its
  # own resolution is the worst combination of the two, so the plan renders whenever anything
  # needs you — the status stays right about the present, untouched.
  it "shows where the money goes when a pool needs you on a covered period", :aggregate_failures do
    dentist = create(:pool, :budget_pool, user: user, account: checking, name: "Dentist", priority: 1)
    create(:pool_budget, :one_time, pool: dentist, amount: 300, anchor_date: Date.current + 3.days)
    deposit(1_000)

    visit root_path

    expect(page).to have_content("You're covered")
    expect(waterfall_section).to have_content("$300.00 of $300.00")
    # Nothing ran out, so the cutoff must stay away — it used to render at the end of the
    # list with a "$0.00 unfunded" label the moment the waterfall was shown on a covered period.
    expect(waterfall_section).to have_no_content("ran out here")
  end

  # A pool that asked for nothing rendered "$0.00 of $0.00", and below the cutoff that reads
  # as money denied rather than money not wanted.
  it "leaves a pool that asks for nothing out of the waterfall", :aggregate_failures do
    settled = envelope("Rent", 300)
    deposit(500)
    create(:pool_movement, from_pool: checking, to_pool: settled, amount: 300)
    envelope("Groceries", 400, priority: 2)

    visit root_path

    expect(waterfall_section).to have_content("Groceries")
    expect(waterfall_section).to have_no_content("Rent")
    expect(waterfall_section).to have_no_content("$0.00 of $0.00")
  end

  # "Something needs you" is NOT the same question as "is there a plan to show". Two of the
  # three kinds of problem — an overdrawn account and an account-less pool — have no waterfall
  # row at all, and the zero-need reject can empty the list outright. This is the fixture below
  # exactly: one problem, no rows, and the band rendered its heading over nothing, which on a
  # money screen reads as data that failed to load. The other direction is the covered-period
  # example above, where there are rows and the plan does render.
  it "shows no plan when the problems have no waterfall rows", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    expect(page).to have_content("1 thing needs you")
    expect(page).to have_no_content("Where your money goes")
  end

  # An overdrawn account reaches neither #available (clamped at zero) nor #shortfall
  # (summed from the waterfall rows), so unless a band names it, a real $400 debt is
  # invisible on the one screen that exists to say where you stand.
  it "gives an overdrawn account a voice even when every envelope is quiet", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    expect(page).to have_content("Checking is overdrawn $400.00")
    within(attention_section) do
      expect(page).to have_content("1 thing needs you")
      expect(page).to have_content("overdrawn $400.00")
      expect(page).to have_no_content("Nothing needs you")
      # The light-danger fill is the only thing separating this row from any other, and a
      # state's single visual differentiator that nothing asserts is a state nothing pins.
      expect(page).to have_css("div.bg-status-danger-light", text: "overdrawn $400.00")
    end
  end

  # DELETED (plan 3, task 6), all five planted on the account-less pool the tightening abolished:
  #
  #   * "names a pool that belongs to no account" — the band saying it, and the orphan's ask NOT
  #     dragging the shortfall cutoff.
  #   * "does not count a quiet pool with no account as a problem" — the screen every user with
  #     savings goals opened on, five quiet goals counted as five problems above "You're covered".
  #   * "still counts a pool with no account that is asking for money" — the other side of that
  #     narrowing, so it could not be satisfied by an app that simply stopped counting orphans.
  #   * "still counts a pool with no account that is overdrawn" — the `#attention_pools` route in,
  #     which the orphan term must not silence.
  #   * "counts more than one problem in the heading" — pluralisation, planted with an orphan as
  #     the second problem.
  #
  # The heading's pluralisation is the one claim of the five with a life after the tightening, and
  # it is covered by the two-envelope examples above and below. See the note on `#orphan`'s
  # deletion at the top of this file.

  # The state that is short with nothing flagged: every rate envelope reads `left_to_spend`,
  # so no pool needs attention while the period is genuinely $300 down. "Nothing needs you"
  # here would be the exact lie this band exists to prevent.
  it "never says nothing needs you while the money runs out", :aggregate_failures do
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing is flagged, but you're still short")
      expect(page).to have_no_content("Nothing needs you")
      expect(page).to have_content("Where your money goes")
    end
  end

  # Each account drains its own pot, so there is no single moment the money ran out: a line
  # here would print above rows that were funded in full out of another account's cash.
  it "draws no cutoff when the user has more than one account", :aggregate_failures do
    # Checking minted first, so it is the user's main account (main-account spec §6) — the only
    # account an income category may point at. `envelope` touches `checking` and has to run
    # before `ally` is created for that to hold.
    envelope("Rent", 400)
    ally = create(:pool, :account, user: user, name: "Ally")
    deposit(100)
    spare = create(:pool, :budget_pool, user: user, account: ally, name: "Gas", priority: 2)
    create(:pool_budget, :per_period_rate, pool: spare, amount: 200)
    deposit(500, into: ally)

    visit root_path

    expect(waterfall_section).to have_content("$100.00 of $400.00")
    expect(waterfall_section).to have_content("$200.00 of $200.00")
    expect(waterfall_section).to have_no_content("ran out here")
  end

  # The other cutoff branch: the money ran out inside the LAST row, so no pool sits below
  # the line and it has to render at the end of the list rather than not at all.
  it "shows the waterfall with a cutoff when short", :aggregate_failures do
    ["Rent", "Groceries"].each_with_index do |name, i|
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: i + 1)
      create(:pool_budget, :per_period_rate, pool: pool, amount: 500)
    end
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: 700, date: Date.current)

    visit root_path

    expect(page).to have_content("Where your money goes")
    expect(page).to have_content("ran out here")
  end

  # A savings goal whose rule carries a NEGATIVE amount — written past Budget's validation
  # deliberately, exactly as allocation_calculator_spec's twin does, because the shape being
  # defended against is a row that reached the table some other way and that is precisely what a
  # validation cannot promise.
  def broken_goal(name, amount)
    pool = create(
      :pool, :savings_pool, user: user, account: checking, name: name, target_amount: 2_400, priority: 2
    )
    create(:pool_budget, :per_period_rate, pool: pool, amount: amount.abs)
    pool.budgets.first.update_column(:amount, amount) # rubocop:disable Rails/SkipsModelValidations
    pool
  end

  # A RULE WHOSE AMOUNT IS NEGATIVE, and Home is the ROOT ROUTE — this took out the whole app
  # rather than one screen.
  #
  # PoolCalculator#goal_required returns `[rate, remaining].min`, so a savings goal carrying a
  # negative rule asks for a negative figure, and HomePresenter#waterfall_row's
  # `pot.clamp(0.to_d, needed)` raises ArgumentError on it — `BigDecimal("100").clamp(0, -150)`
  # raises. AllocationCalculator#fill was guarded for exactly this in Task 2 and Home's
  # near-duplicate was not, which is what a plan splitting one rule over two files costs.
  #
  # `update_column` writes past Budget's validation deliberately, exactly as
  # allocation_calculator_spec's twin does: the shape being defended against is a row that reached
  # the table some other way, which is precisely what a validation cannot promise.
  #
  # BOTH SIDES OF THE GUARD, and they are independent: the raw reader is still negative (that is
  # the input), while the SCREEN renders and #total_required counts the bad rule as zero rather
  # than subtracting $150 from what the user owes — a wrong total is worse than a crash on a money
  # screen, and only the floor prevents both.
  it "renders when a rule's amount is negative", :aggregate_failures do
    vacation = broken_goal("Vacation", -150)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_content("$300.00 short this period")
    expect(waterfall_section).to have_content("$100.00 of $400.00")
    expect(Pool.find(vacation.id).calculator.required).to eq(-150)
    expect(HomePresenter.new(user: user).total_required).to eq(400)
  end

  # FINDING 4: THE TWO BANDS ANSWER DIFFERENT QUESTIONS AND NOW SAY SO.
  #
  # The problem row offers PoolStatus#funding_gap — the whole cumulative hole, read from the live
  # balance. The waterfall row prints #required — THIS period's share of it, post-sweep. Both are
  # right (see HomePresenter#fix_amount_for) and neither figure changes; what was missing was
  # anything on the screen saying they are measured over different spans. On the demo they read
  # `Take $553.85` and `$35.00 of $171.43` inches apart.
  #
  # Car Insurance is $1,200 every six months due six biweekly boundaries out, so this period's
  # share is a stable $171.43 whatever day the suite runs — while the steady-schedule gap depends
  # on how many boundaries fall inside a six-month cycle on that calendar, so it is READ rather
  # than pinned to a second literal. Rent takes the pot first, which is what keeps Car's row short
  # and therefore keeps its button: a pool the waterfall funds in full is deliberately offered no
  # move at all.
  describe "the whole gap above, this period's share below" do
    before do
      envelope("Rent", 1_000, priority: 0)
      car = create(:pool, :budget_pool, user: user, account: checking, name: "Car Insurance", priority: 1)
      create(:pool_budget, pool: car, amount: 1_200, interval_months: 6, anchor_date: Date.current + 84)
      deposit(1_100)
      visit root_path
    end

    def gap = user.pools.find_by!(name: "Car Insurance").status.funding_gap.round(2)

    it "prints both figures for one envelope, inches apart", :aggregate_failures do
      expect(gap).to be > 171.43 # the whole hole really is bigger than this period's share
      within(find("[data-problem-pool='Car Insurance']")) do
        expect(page).to have_link("Take #{number_to_currency(gap)} from Checking buffer")
      end
      within(waterfall_section) { expect(page).to have_content("$100.00 of $171.43") }
    end

    # The bridge. A BAND LABEL, not a seventh clause on every row — said once, above the rows.
    it "labels the band so the two are not read as two answers to one question", :aggregate_failures do
      within(waterfall_section) do
        expect(page).to have_content("This period's share — what the next distribution puts in, not the whole gap.")
      end
      expect(waterfall_section.text.scan("This period's share").size).to eq(1)
      expect(find("[data-problem-pool='Car Insurance']")).to have_no_content("This period's share")
    end
  end

  # WHICH PERIOD THE FIGURE BELONGS TO, IN THE ATTENTION BAND — the suffix this band was the one
  # caller in the app to omit.
  #
  # `#pool_problem_label` passed `changed_after_distributing:` and NOT `period_closed:`, so ONE
  # Home render printed `overdrawn $80.00 · last period` in the pools band and `overdrawn $80.00`
  # in the attention band a few inches above it — the exact defect Task 3's fix round closed
  # between Home and /budget, reintroduced between Home's own two bands. Both bands are asserted
  # here, on one visit, because that is where the disagreement was visible.
  #
  # THE PAIR IS THE POINT. Two rate envelopes with the SAME rule, the SAME spending and therefore
  # the same `overdrawn $80.00`, differing only in which side of a period boundary their money
  # arrived on. A lone closed-period row would pass against a suffix printed unconditionally.
  #
  # :overdrawn rather than :behind because `PoolCalculator#period_closed?` is false for a pool with
  # any anchored rule (`rate_budgets` would be empty), and :overdrawn is the one attention state
  # guarded on the balance alone — so it is the only state a rate envelope can be in AND have a
  # closed period.
  describe "an overdrawn envelope whose period has ended" do
    before do
      deposit(2_000)
      swept = envelope("Swept", 400, priority: 1)
      live = envelope("Live", 400, priority: 2)
      # Two periods back on a biweekly cadence anchored today, so the rate rule's own period —
      # measured from `last_funded_on`, which is this movement — closed before today.
      create(:pool_movement, from_pool: checking, to_pool: swept, amount: 100, date: Date.current - 21.days)
      create(:pool_movement, from_pool: checking, to_pool: live, amount: 100, date: Date.current)
      spend(swept, 180)
      spend(live, 180)
      visit root_path
    end

    def spend(pool, amount)
      category = create(:category, :expense, user: user, pool: pool, name: "#{pool.name} spend")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    it "marks the closed period on the problem row, and only on that one", :aggregate_failures do
      expect(find("[data-problem-pool='Swept']")).to have_content("overdrawn $80.00 · last period")
      within(find("[data-problem-pool='Live']")) do
        expect(page).to have_content("overdrawn $80.00")
        expect(page).to have_no_content("last period")
      end
    end

    # THE TWO BANDS, ONE SCREEN, ONE VISIT. This is the assertion the defect would have failed:
    # the same pool, rendered inches apart, read `overdrawn $80.00 · last period` below and
    # `overdrawn $80.00` above. Compared to a literal on both sides rather than to each other, so
    # a label that lost its amount fails here rather than agreeing with itself about nothing.
    it "reads the same in the attention band as in the pools band", :aggregate_failures do
      expect(find("[data-problem-pool='Swept']")).to have_content("overdrawn $80.00 · last period")
      expect(find("[data-pool-name='Swept']")).to have_content("overdrawn $80.00 · last period")
      expect(find("[data-problem-pool='Live']")).to have_no_content("last period")
      expect(find("[data-pool-name='Live']")).to have_no_content("last period")
    end
  end

  # The cutoff sits where the money ran out, and a pool funded $200 of $500 did receive
  # money: it belongs ABOVE the line, with only the pools that got nothing below it.
  it "draws the cutoff beneath the last pool that got any money", :aggregate_failures do
    { "Rent" => 500, "Groceries" => 500, "Dentist" => 500 }.each_with_index do |(name, amount), i|
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: i + 1)
      create(:pool_budget, :per_period_rate, pool: pool, amount: amount)
    end
    deposit(700)

    visit root_path

    expect(waterfall_section.text).to match(/Rent.*Groceries.*ran out here.*Dentist/m)
    expect(waterfall_section).to have_content("$200.00 of $500.00")
    expect(waterfall_section).to have_content("$0.00 of $500.00")
    expect(waterfall_section).to have_content("$800.00 unfunded")
  end
end
