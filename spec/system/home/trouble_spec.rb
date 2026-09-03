# frozen_string_literal: true

require "rails_helper"

# HOME'S TROUBLE STRIP — rendered ONLY when something real needs a human (answers-first spec §5).
# This file is `spec/system/home/attention_spec.rb`'s successor.
#
# ** SILENCE IS THE GOOD STATE. ** The band this replaces rendered on every page load with one of
# three headings, two of which said nothing needed doing; there is no permanent "Nothing needs you"
# box any more, so the absence of the strip IS the good news and every trigger below is asserted in
# BOTH directions.
#
# ── CARRIED FROM attention_spec.rb:
#
#   * "lists a category that can't be funded in time" → carried whole (`won't make it`, Dentist).
#   * "says nothing needs you when every category is quiet" → INVERTED into "renders nothing at all
#     when nothing is wrong": the same fixture, and the strip is absent rather than reassuring.
#   * "names an overdrawn account without counting it as something that needs you" → the pot half is
#     the hero's (`hero_spec`); the strip half survives as the :overdraft trigger, which is now a
#     NON-MAIN account (see below).
#   * "renders when a rule's amount is negative" → carried whole. Home is the root route, so this
#     took out the whole app rather than one screen.
#   * the "overdrawn category whose period has ended" pair → carried: the ` · last period` suffix on
#     the strip's row, and the same-sentence-in-both-places pin now compares the strip against the
#     "This period" section's clause.
#   * the "changed a rule after distributing" group (five examples) → carried whole from
#     `categories_spec.rb`, where its fixtures lived; the strip is the second place the clause has
#     to read the same, so the pin lives here.
#   * "shows an overdue category with the date that passed and the rule behind it", "shows a behind
#     category with the rule it is behind on", "explains an overdrawn rate category by its rate",
#     "says so plainly when an overdrawn category has no rules at all", "auto-expands a category
#     that needs attention" → all five carried from `categories_spec.rb`. The rule detail they
#     assert is re-housed here, which is where the auto-expand rule ("anything needing attention
#     opens itself") describes the whole population.
#
# ── CARRIED FROM hero_spec.rb (the plan's Task 1 → Task 2 hand-over):
#
#   * "names a non-main account that has gone below zero" — the strip claims it, copy verbatim.
#   * all six sacrifice-link examples. §9's permanent button is a fifth trigger here: a strip that
#     renders only when something is true cannot carry a button that renders always, and "your
#     budget doesn't fit your income" is the most permanent true thing on the screen.
#
# ── DELETED WITH THE ATTENTION BAND (nine titles). The band held a WATERFALL — "Where your money
# goes", the fill order and the cutoff — and spec §1 rules that Home stops showing the system. The
# plan it drew is the mechanic's view of the distribution and lives on `/distributions/new`, which
# the strip's own Distribute button opens.
#
#   * "shows no waterfall when there is no gap to explain"
#   * "shows where the money goes when a category needs you on a covered period" — its $700 free
#     figure survives in `hero_spec`; the waterfall half goes.
#   * "leaves a category that asks for nothing out of the waterfall"
#   * "shows no plan when the problem has no waterfall row"
#   * "never says nothing needs you while the money runs out" — the heading it pinned is gone. The
#     state it was about (short with nothing flagged) is now the hero's negative free figure, and
#     the strip's :undistributed trigger is what asks the user to act on it.
#   * "shows the waterfall with a cutoff when short"
#   * "draws the cutoff beneath the last category that got any money"
#   * "the whole gap above, this period's share below" (two examples) — the bridge label existed to
#     keep two bands on one screen from reading as two answers; there is one band now.
#
# EVERY COPY ASSERTION IN THIS FILE GOES THROUGH A DATA HOOK — `[data-trouble]`,
# `[data-problem-category]`, `[data-overdrawn-account]`, `[data-undistributed]`,
# `[data-sacrifice-link]`, `[data-role='holding-detail']`.
RSpec.describe "Home Trouble", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `checking` FIRST, so it is the account the `:account` trait nominates as main — every category
  # the helpers below mint would otherwise pull the factory's own account into being and claim the
  # nomination.
  before do
    checking
    sign_in user, scope: :user
  end

  def strip = find("[data-trouble]")

  def problem_row(name) = find("[data-problem-category='#{name}']")

  def holder(name, priority: 1, **attrs)
    create(
      :category,
      :expense,
      user: user,
      name: name,
      priority: priority,
      funded_since: Date.current - 1.year,
      **attrs
    )
  end

  def envelope(name, amount, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: amount)
    end
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  def fund(category, amount, on: Time.zone.now)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  def spend(category, amount, on: Date.current)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A dated bill the user actually pays: an item is the only fulfilment signal BudgetCalculator
  # accepts, and therefore the only way a rule can be overdue rather than settled by its own date.
  def payable(name, amount:, due:, interval: 1, priority: 1)
    holder(name, priority: priority).tap do |category|
      item = create(:item, category: category, name: "#{name} Bill")
      create(
        :budget,
        category: category,
        item: item,
        amount: amount,
        interval_months: interval,
        anchor_date: due
      )
    end
  end

  # A bill that accumulates toward a date — the shape that reads `behind` when it is off schedule.
  def accumulating(name, amount:, due:, priority: 1, every: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: every, anchor_date: due)
    end
  end

  # A MOVE ON THE PHYSICAL LEDGER, out of Checking and into a second account. It is the only way to
  # put one account in the red while every category and available stay healthy.
  def move_out(amount)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(
      :account_movement,
      from_pool: checking,
      to_pool: ally,
      amount: amount,
      date: Date.current,
      kind: :transfer
    )
  end

  # THE DISTRIBUTION THAT SILENCES THE :undistributed TRIGGER — one `Allocation.distributed` row
  # inside this period, which is exactly what `DistributionClock` looks for.
  def distribute(category, amount)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: Time.zone.now)
  end

  # ── THE STRIP'S ABSENCE, WHICH IS THE DESIGN (spec §5) ─────────────────────────────────────────

  # INVERTED FROM "says nothing needs you when every category is quiet": the same fixture, and now
  # there is no box at all. A permanent placeholder is exactly what §5 rules out.
  it "renders nothing at all when nothing is wrong", :aggregate_failures do
    deposit(400)
    distribute(envelope("Groceries", 400), 400)

    visit root_path

    expect(page).to have_css("[data-hero]")
    expect(page).to have_no_css("[data-trouble]")
    expect(page).to have_no_content("Nothing needs you")
    expect(page).to have_no_content("needs you")
  end

  # ── TRIGGER 1: AN OVERDUE OR UNREACHABLE BILL ──────────────────────────────────────────────────

  # CARRIED WHOLE from "lists a category that can't be funded in time". The token distribution is
  # what keeps the count at ONE: without it this period is also undistributed, and the singular
  # heading — which is the thing a plural bug shows up in — would never be reachable here.
  it "shows a category that can't be funded in time", :aggregate_failures do
    dentist = holder("Dentist")
    create(:budget, :one_time, category: dentist, amount: 300, anchor_date: Date.current + 3.days)
    distribute(dentist, 10)

    visit root_path

    expect(strip).to have_content("won't make it")
    expect(problem_row("Dentist")).to have_content("Dentist")
    expect(strip).to have_content("1 thing needs you")
  end

  # THE OTHER DIRECTION: the same category funded in time is not in the strip at all.
  it "leaves a bill the schedule can still reach out of the strip", :aggregate_failures do
    deposit(2_000)
    dentist = holder("Dentist")
    create(:budget, :one_time, category: dentist, amount: 300, anchor_date: Date.current + 3.days)
    distribute(dentist, 300)

    visit root_path

    expect(page).to have_no_css("[data-problem-category='Dentist']")
    expect(page).to have_no_css("[data-trouble]")
  end

  # CARRIED FROM categories_spec: the two states that render a date the user has to act on, seen
  # through a real row — which is where the date and the rule beneath it actually meet.
  it "shows an overdue category with the date that passed and the rule behind it", :aggregate_failures do
    payable("Utilities", amount: 120, due: Date.current - 10.days)

    visit root_path

    expect(problem_row("Utilities"))
      .to have_content("overdue · was #{(Date.current - 10.days).strftime("%b %-d")}")
    expect(problem_row("Utilities")).to have_css("[data-role='holding-detail']")
    expect(problem_row("Utilities")).to have_content("Utilities Bill")
    expect(problem_row("Utilities")).to have_content("$120.00 · #{(Date.current - 10.days).strftime("%b %-d")}")
  end

  # CARRIED FROM categories_spec. The lag is a function of how many boundaries fall inside the
  # cycle, so the figure is matched by shape rather than pinned to date arithmetic this example
  # does not own.
  it "shows a behind category with the rule it is behind on", :aggregate_failures do
    accumulating("Car Insurance", amount: 1_200, due: Date.current + 3.months, every: 6)

    visit root_path

    expect(problem_row("Car Insurance")).to have_content(/behind \$\d[\d,]*\.\d\d/)
    expect(problem_row("Car Insurance")).to have_content("Every 6 months")
    expect(problem_row("Car Insurance"))
      .to have_content("$1,200.00 · #{(Date.current + 3.months).strftime("%b %-d")}")
  end

  # ── TRIGGER 2: AN OVERDRAWN CATEGORY ───────────────────────────────────────────────────────────

  # CARRIED FROM categories_spec, both halves. `rules.empty?` does NOT imply a rate rule exists: a
  # category with no rules at all and a negative holding reaches :overdrawn — the only state guarded
  # on the balance alone — so the fallback sentence has to be true of what is actually there.
  it "explains an overdrawn rate category by its rate", :aggregate_failures do
    deposit(200)
    dining = envelope("Dining Out", 150)
    fund(dining, 100)
    spend(dining, 180)

    visit root_path

    expect(problem_row("Dining Out")).to have_content("overdrawn $80.00")
    expect(problem_row("Dining Out")).to have_content("refills at its rate")
    expect(problem_row("Dining Out")).to have_no_content("nothing fills it")
  end

  it "says so plainly when an overdrawn category has no rules at all", :aggregate_failures do
    mystery = holder("Mystery")
    spend(mystery, 80)

    visit root_path

    expect(problem_row("Mystery")).to have_content("overdrawn $80.00")
    expect(problem_row("Mystery")).to have_content("nothing fills it")
    expect(problem_row("Mystery")).to have_no_content("refills at its rate")
  end

  # WHICH PERIOD THE FIGURE BELONGS TO, and the pair is the point: two rate categories with the SAME
  # rule, the SAME spending and therefore the same `overdrawn $80.00`, differing only in which side
  # of a period boundary their money arrived on.
  describe "an overdrawn category whose period has ended" do
    before do
      deposit(2_000)
      swept = envelope("Swept", 400, priority: 1)
      live = envelope("Live", 400, priority: 2)
      fund(swept, 100, on: Date.current - 21.days)
      fund(live, 100, on: Date.current)
      spend(swept, 180)
      spend(live, 180)
      visit root_path
    end

    it "marks the closed period on the problem row, and only on that one", :aggregate_failures do
      expect(problem_row("Swept")).to have_content("overdrawn $80.00 · last period")
      expect(problem_row("Live")).to have_content("overdrawn $80.00")
      expect(problem_row("Live")).to have_no_content("last period")
    end

    # THE TWO SECTIONS RENDER THE SAME CATEGORY INCHES APART, and an overdrawn one is in both by
    # construction. Compared to a literal on both sides rather than to each other, so a clause that
    # lost its amount fails here rather than agreeing with itself about nothing.
    it "reads the same in the strip as in the period section", :aggregate_failures do
      expect(problem_row("Swept")).to have_content("overdrawn $80.00 · last period")
      expect(find("[data-period-row='Swept'] [data-period-clause]"))
        .to have_content("overdrawn $80.00 · last period")
      expect(problem_row("Live")).to have_no_content("last period")
      expect(find("[data-period-row='Live'] [data-period-clause]")).to have_no_content("last period")
    end
  end

  # ── TRIGGER 3: A PHYSICAL OVERDRAFT ────────────────────────────────────────────────────────────

  # CLAIMED FROM THE HERO CARD (the plan's Task 1 → Task 2 hand-over), copy verbatim. It is a
  # NON-MAIN account: main's overdraft IS the red "In Checking" figure with its own sentence (spec
  # §2), and printing the same debt twice with two different sentences about what counts it is worse
  # than printing it once.
  it "names a non-main account that has gone below zero", :aggregate_failures do
    deposit(1_000)
    move_in(200)

    visit root_path

    expect(strip).to have_css("[data-overdrawn-account='Ally']", text: "Ally is overdrawn $200.00")
    expect(strip).to have_content("none of the figures above count it")
    # The pot is fine — $1,000 of income plus the $200 that walked in — so the hero's figure must
    # not have turned red as well.
    expect(page).to have_no_css("[data-in-checking].text-status-danger")
  end

  # THE MIRROR OF #move_out: a second account paying INTO checking, which is the only way to put a
  # NON-main account below zero while every category and available stay healthy.
  def move_in(amount)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(
      :account_movement,
      from_pool: ally,
      to_pool: checking,
      amount: amount,
      date: Date.current,
      kind: :transfer
    )
  end

  # THE OTHER DIRECTION, and it is the one that keeps the debt from being reported twice: main is
  # overdrawn, the hero says so in red, and the strip does not repeat it.
  it "leaves main's own overdraft to the hero", :aggregate_failures do
    deposit(500)
    move_out(900)
    distribute(envelope("Groceries", 400), 400)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]", text: "already spent past zero")
    expect(page).to have_no_css("[data-overdrawn-account='Checking']")
  end

  # ── TRIGGER 4: A PERIOD NOBODY HAS DISTRIBUTED ─────────────────────────────────────────────────

  # §6: "The distribute call-to-action lives on the trouble strip when undistributed, not as a
  # band." The link is asserted with its href, because a call to action that goes nowhere looks
  # identical to one that works.
  it "asks the user to distribute when this period's money has not been handed out", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", 400)

    visit root_path

    expect(find("[data-undistributed]")).to have_content("This period hasn't been distributed yet")
    expect(find("[data-undistributed]"))
      .to have_link("Distribute this period", href: new_distribution_path)
  end

  # THE OTHER DIRECTION: one distributed allocation inside the period, and the trigger falls silent.
  it "falls silent once this period has been distributed", :aggregate_failures do
    deposit(1_000)
    distribute(envelope("Groceries", 400), 400)

    visit root_path

    expect(page).to have_no_css("[data-undistributed]")
    expect(page).to have_no_link("Distribute this period")
  end

  # A USER WITH NOTHING TO DISTRIBUTE IS NOT IN TROUBLE. Every fresh account has an undistributed
  # period by definition, and a strip that fired on it would greet every new user with a demand they
  # cannot act on.
  it "asks nothing of a user whose rules ask for nothing", :aggregate_failures do
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-undistributed]")
    expect(page).to have_no_css("[data-trouble]")
  end

  # ── TRIGGER 5: THE BUDGET DOES NOT FIT THE INCOME (§9's permanent button, claimed from the hero) ─

  # The href is asserted, not just the label: a button that says the budget does not fit and goes
  # nowhere is the state this replaced, and it looked identical.
  it "shows the structural warning only when rules exceed typical income", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path

    expect(strip).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
    expect(strip).to have_css("[data-sacrifice-link]")
  end

  it "hides the structural warning when the budget fits", :aggregate_failures do
    deposit(1_000)
    distribute(envelope("Groceries", 400), 400)

    visit root_path

    expect(page).to have_no_link("Your budget doesn't fit your income")
    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # THE BUTTON AND THE ROUTE ARE THE SAME CONDITION READ TWICE. Home shows it on
  # `structurally_underwater?` and /sacrifice refuses on the same test, so a button that rendered
  # where the route refuses would open a redirect straight back. Followed rather than merely
  # asserted, because only following it can tell the two apart.
  it "opens the sacrifice view when followed", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path
    click_link "Your budget doesn't fit your income"

    expect(page).to have_current_path(sacrifice_path)
    expect(page).to have_content("$600.00 underwater every period")
  end

  # THE HERO AND THE BUTTON ANSWER DIFFERENT QUESTIONS, which is why §9 asks for the button to be
  # permanent. This period's cash is fine — the money is in the account — and the budget still does
  # not fit the income.
  it "keeps the button up on a period whose cash is comfortable", :aggregate_failures do
    rent = envelope("Rent", 3_000)
    deposit(5_000)
    distribute(rent, 3_000)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "$2,000.00")
    expect(strip).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
  end

  it "shows no structural warning before an income is declared" do
    user.update!(typical_income: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # INCOME WITHOUT A CADENCE IS REACHABLE — the declaration form offers "Not set" for the period —
  # and `Budget.steady_need` still answers there, against a period the user has not agreed to. The
  # gate is both halves, and this is the half that only fails when one of them is dropped.
  it "shows no structural warning before a period is declared" do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # ── THE FIX, AND THE SCREEN THAT MUST NOT FALL OVER ────────────────────────────────────────────

  # CARRIED WHOLE. A rule whose amount is negative took out the ROOT ROUTE rather than one screen:
  # `HoldingCalculator#goal_required` returns `[rate, remaining].min`, so a goal carrying a negative
  # rule asks for a negative figure and the waterfall's `remaining.clamp(0.to_d, needed)` raises.
  #
  # BOTH SIDES OF THE GUARD, and they are independent: the raw reader is still negative (that is the
  # input), while the SCREEN renders and #remaining_plan counts the bad rule as zero rather than
  # subtracting $150 from what the user owes.
  it "renders when a rule's amount is negative", :aggregate_failures do
    vacation = holder("Vacation", priority: 2, target_amount: 2_400)
    create(:budget, :per_period_rate, category: vacation, amount: 150)
    vacation.budgets.first.update_column(:amount, -150) # rubocop:disable Rails/SkipsModelValidations
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "-$300.00")
    expect(Category.find(vacation.id).holding_calculator.required).to eq(-150)
    expect(HomePresenter.new(user: user).remaining_plan).to eq(400)
  end

  # ── SPEC §8'S ONE ROUGH EDGE, CARRIED FROM categories_spec ─────────────────────────────────────
  #
  # Rule changes apply immediately, so raising a rule the day after a distribution flips its
  # category from `on track` to `behind` with no money missing and nothing having gone wrong. The
  # row says which of the two kinds of `behind` it is.
  #
  # `travel_to` only around the WRITES, never around `visit`: the whole clause is a comparison of
  # two timestamps, and without a controlled clock the rule and the allocation are written
  # milliseconds apart and this is a coin toss.
  describe "a category that went behind because a rule was changed" do
    include_context "with a rule changed after the money went out"

    def accumulating_rule(name, amount:, priority:)
      category = holder(name, priority: priority)
      rule = create(
        :budget,
        category: category,
        amount: amount,
        interval_months: 6,
        anchor_date: today + 3.months
      )
      [category, rule]
    end

    # THE PAIR THE CLAUSE HAS TO TELL APART: two categories with the same shape of rule, the same
    # distribution and the same `behind` state, differing only in which side of that distribution
    # their rule was last edited on.
    def plant_pair
      deposit(2_000)
      raised = raised_rule = steady = nil

      before_distributing do
        raised, raised_rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1)
        steady, = accumulating_rule("Property Tax", amount: 1_200, priority: 2)
      end

      [raised, steady].each { |category| allocate(category, 10) }
      after_distributing { raised_rule.update!(amount: 1_800) }
    end

    # BOTH DIRECTIONS ON ONE SCREEN, and that is the point rather than a convenience.
    it "says so on that row and on no other", :aggregate_failures do
      plant_pair

      visit root_path

      expect(problem_row("Car Insurance")).to have_content("behind")
      expect(problem_row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(problem_row("Property Tax")).to have_content("behind")
      expect(problem_row("Property Tax")).to have_no_content("you changed a rule here after distributing")
    end

    # THE TWO SECTIONS RENDER THE SAME CATEGORY INCHES APART, and a `behind` category is in both by
    # construction. One explaining the state while the other did not would read as the screen
    # disagreeing with itself about why.
    it "says the same thing in the period section" do
      plant_pair

      visit root_path

      expect(find("[data-period-row='Car Insurance'] [data-period-clause]"))
        .to have_content("you changed a rule here after distributing")
    end

    # THE CASE THAT WOULD HAVE MADE THE OLD COPY A LIE. `updated_at` records WHEN a rule moved and
    # nothing about which way: the rule below goes DOWN, from $1,800 to $1,200, and the category is
    # still behind against the smaller requirement.
    it "says a rule changed, not raised, when the rule went down", :aggregate_failures do
      deposit(2_000)
      category = rule = nil

      before_distributing { category, rule = accumulating_rule("Car Insurance", amount: 1_800, priority: 1) }
      allocate(category, 10)
      after_distributing { rule.update!(amount: 1_200) }

      visit root_path

      expect(problem_row("Car Insurance")).to have_content("behind")
      expect(problem_row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(problem_row("Car Insurance")).to have_no_content("raised")
    end

    # NO DISTRIBUTION, NO CLAUSE. A rule changed on a period nobody has distributed yet has not been
    # changed "after distributing".
    it "stays silent when nothing has been distributed this period", :aggregate_failures do
      deposit(2_000)
      rule = nil

      before_distributing { _, rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1) }
      after_distributing { rule.update!(amount: 1_800) }

      visit root_path

      expect(problem_row("Car Insurance")).to have_content("behind")
      expect(problem_row("Car Insurance")).to have_no_content("you changed a rule here after distributing")
    end

    # THE CLAUSE BELONGS TO `behind` AND TO NOTHING ELSE. An overdue bill is overdue because it was
    # not paid; an edited rule has nothing to do with it, and the aside would be unexplained noise
    # on the loudest row on the screen.
    it "stays off a row in another state", :aggregate_failures do
      deposit(2_000)
      category = payable("Utilities", amount: 120, due: Date.current - 10.days)
      rule = category.budgets.first

      allocate(category, 10)
      after_distributing { rule.update!(amount: 180) }

      visit root_path

      expect(problem_row("Utilities")).to have_content("overdue")
      expect(problem_row("Utilities")).to have_no_content("you changed a rule here after distributing")
    end
  end

  # ── THE NARROW BREAKPOINT ──────────────────────────────────────────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT via CDP — `hero_spec.rb`'s mechanism, copied deliberately: Chrome
  # refuses a headless window narrower than 500px, so `resize_to(375, …)` is really a 500px test.
  # No `evaluate_script` anywhere in the example, for that file's measured reason.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # RENT TAKES THE ROOT FIRST, which is what keeps Dentist's button on the screen at all: a
    # category the next distribution funds in full is deliberately offered no move (see
    # `HomePresenter#covered_by_waterfall?`), and the button is the widest thing this row can hold.
    it "fits a problem row and its fix button inside a 375px viewport", :aggregate_failures do
      deposit(2_000)
      envelope("Rent", 1_500, priority: 0)
      dentist = holder("Dentist", priority: 1)
      create(:budget, :one_time, category: dentist, amount: 1_500, anchor_date: Date.current + 3.days)

      visit root_path

      expect(problem_row("Dentist")).to have_link("Take $1,500.00 from Available")

      panel = page.find("[data-trouble]").native.rect
      button = problem_row("Dentist").find_link("Take $1,500.00 from Available").native.rect

      expect(panel.x + panel.width).to be <= 375
      expect(button.x + button.width).to be <= panel.x + panel.width
    end
  end
end
