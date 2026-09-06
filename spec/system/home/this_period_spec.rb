# frozen_string_literal: true

require "rails_helper"

# HOME'S "THIS PERIOD" — ONE BLOCK PER CATEGORY, ONE ROW PER RULE (two-shapes spec §3). This file is
# its own predecessor's successor twice over: `categories_spec.rb` → the flat claim rows → these
# blocks.
#
# ** THE RULING THIS REBUILD ENCODES (Henry, 2026-09-05): "almost all categories will have multiple
# rules, so we need to base the UI knowing this." ** The section was a row per category with the
# second and third rule indented under the first, which reads as a category with footnotes. It is a
# BLOCK now — a header saying how many rules and what they claim between them, and a row per rule
# saying what SHAPE it is, what it HAS, and WHEN.
#
# ── CARRIED, at their own figures, with three changes that touch every example:
#
#   * THE HOOKS. `[data-period-row='<category>']` → `[data-category-block='<category>']` with
#     `[data-rule-row='<lane>']` inside it; `[data-period-figure]` → `[data-rule-figure]`;
#     `[data-period-bar]` → `[data-rule-bar]`; `[data-period-clause]` → `[data-rule-when]`. A row is
#     named by its LANE now (the item, or "Whole category"), because a block may carry two rows and
#     both would answer to the category's name.
#   * THE DATED FIGURE LOST TWO WORDS. `$424.00 built up of $2,400.00` → `$424.00 of $2,400.00`
#     (`HomeHelper#figure_words`). Neither figure moved. The old wording survived on the Budget page
#     and the categories card for one task, off a second helper; Task 3 folded both screens onto this
#     one and DELETED `#claim_figure` and `#claim_schedule`, so the three screens say one sentence.
#   * THE CLAUSE IS THE STATE AND THE DAY, not the schedule. `next due Oct 9 · $60.00 per period` →
#     `Oct 9 · +$60.00`, and a rate row gains one it never had: `resets <the next boundary>`.
#
# ── DELETED, each at its own site with the reason: "sorts trouble first and keeps fill order behind
# it" (there is one ordering now, the give-way walk, and trouble is a TINT), and the days-left half
# of the heading (the period belongs to `runway_spec.rb`).
#
# ── NEW WITH §3: the block header (rule count, claimed), the two-rule block with a stripe per type,
# the trouble tint, the shape clause per shape, and the give-way sentence under the section.
RSpec.describe "Home This Period", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `sign_in` touches `user` at REAL NOW, which is what keeps `period_anchor_date: Date.current`
  # from being resolved inside a `travel_to` further down this file (CLAUDE.md's third flake cause).
  before do
    checking
    sign_in user, scope: :user
  end

  def section = find("[data-this-period]")

  def block(name) = find("[data-category-block='#{name}']")

  # A ROW IS FOUND INSIDE ITS BLOCK, always: two categories may both carry a "Whole category" row,
  # and a page-wide find would be ambiguous on exactly the two-block screens this file plants.
  def rule_row(category, lane: "Whole category") = block(category).find("[data-rule-row='#{lane}']")

  def figure(category, lane: "Whole category") = rule_row(category, lane: lane).find("[data-rule-figure]")

  def when_clause(category, lane: "Whole category") = rule_row(category, lane: lane).find("[data-rule-when]")

  # A CATEGORY THAT HOLDS MONEY (spec §3): an expense category with a `funded_since`, a year before
  # the day the dated examples travel to — so every entry this file dates "today" counts against it.
  #
  # ** THE DATE IS A LITERAL AND NOT `Date.current - 1.year` (fix wave — LOW-6; CLAUDE.md's third
  # flake cause). ** The fixtures are built at REAL NOW and the dated examples then read the screen
  # inside `travel_to(Date.new(2026, 8, 20))`, so a wall-clock funding date walks forward one day per
  # day while the travelled `today` does not: on 2027-08-21 it lands AFTER the day the walk is read
  # against, `ClaimCalculator#accrual_start` opens on a day that has not arrived, and every figure in
  # this file goes to zero. The failure would be stable BY NAME and attributable to any commit that
  # happened to be current, which is what makes the clock the worst of the three causes.
  def a_year_before_the_travelled_day = Date.new(2025, 8, 20)

  def holder(name, priority: 1, **attrs)
    create(
      :category,
      :expense,
      user: user,
      name: name,
      priority: priority,
      funded_since: a_year_before_the_travelled_day,
      **attrs
    )
  end

  # A rate category: refilled every period, and the shape whose figure is `spent of rate`.
  def envelope(name, rate:, priority: 1, type: :usage)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: rate, rule_type: type)
    end
  end

  # A bill that accrues toward a date (§3.2). `created_at:` is planted wherever the walk has to reach
  # back (the ruling of 2026-09-03): a rule accrues from the LATER of its category's `funded_since`
  # and its own birthday, so a rule the factory writes at real-now walks nothing inside a `travel_to`
  # that has gone backwards.
  def accumulating(name, amount:, due:, priority: 1, **plant)
    rule = plant.extract!(:created_at)
    holder(name, priority: priority, **plant).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: 1, anchor_date: due, **rule)
    end
  end

  # THE FIXED GRID THREE EXAMPLES SHARE: biweekly anchored Aug 14 2026, `today` Aug 20, and a rule
  # born on that boundary so §3.2's walk opens there and every figure they plant is derivable.
  # `periods_left` from Aug 14 to the Oct 9 due date counts Aug 14, Aug 28, Sep 11, Sep 25, Oct 9 = 5.
  def on_the_fixed_grid(name, amount:)
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    accumulating(
      name,
      amount: amount,
      due: Date.new(2026, 10, 9),
      funded_since: Date.new(2026, 8, 14),
      created_at: Time.zone.local(2026, 8, 14)
    )
  end

  # A ONE-TIME BILL ON AN ITEM, ON THE FIXED GRID, DUE INSIDE THE PERIOD — the shape whose
  # occurrence never rolls and which therefore needed the paid arm. Returns the ITEM, because the
  # example settles the rule by spending on its lane.
  def one_off_bill_on_the_fixed_grid
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    deposit(2_000)
    utilities = holder("Utilities", funded_since: Date.new(2026, 8, 14))
    create(:item, category: utilities, name: "Water").tap do |water|
      create(
        :budget,
        :one_time,
        category: utilities,
        item: water,
        amount: 600,
        anchor_date: Date.new(2026, 8, 24),
        created_at: Time.zone.local(2026, 8, 14)
      )
    end
  end

  # A ONE-TIME BILL ON AN ITEM, ON THE FIXED GRID, DUE INSIDE THE PERIOD — the shape whose occurrence
  # never rolls and which therefore needed the paid arm. Returns the ITEM, because the example
  # settles the rule by spending on its lane.
  def one_off_bill_on_the_fixed_grid
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    deposit(2_000)
    utilities = holder("Utilities", funded_since: Date.new(2026, 8, 14))
    create(:item, category: utilities, name: "Water").tap do |water|
      create(
        :budget,
        :one_time,
        category: utilities,
        item: water,
        amount: 600,
        anchor_date: Date.new(2026, 8, 24),
        created_at: Time.zone.local(2026, 8, 14)
      )
    end
  end

  # ** A GOAL IS A DATED RULE WHOSE AMOUNT IS ITS TARGET (§2 row 5). ** `periods:` is what the share
  # is derived from: on the biweekly grid this file declares, `periods` fortnights from today closes
  # on `today + 14 × periods − 1`, so §3.2's catch-up asks `target ÷ periods` in the first period and
  # every literal below is that division.
  def goal(name, target:, periods: 1, priority: 1, type: :usage)
    holder(name, priority: priority).tap do |category|
      create(
        :budget,
        category: category,
        amount: target,
        basis: :monthly,
        interval_months: nil,
        rule_type: type,
        anchor_date: Date.current + ((14 * periods) - 1).days
      )
    end
  end

  def header(name) = block(name).find("[data-block-header]")

  # A SECOND RULE ON A CATEGORY, ON ONE OF ITS ITEMS — the shape a block exists for, and the only
  # one `Budget#category_may_hold_one_item_less_rule` allows beside the catch-all.
  def second_rule(category, name, rate:, type: :usage)
    create(
      :budget,
      :per_period_rate,
      category: category,
      amount: rate,
      rule_type: type,
      item: create(:item, category: category, name: name)
    )
  end

  # A BILL THAT COMES ROUND ONCE A YEAR — `every 12 months` in the row's own words. Born on
  # `#a_year_before_the_travelled_day`, the day the dated examples read, so §3.2's walk has periods to visit
  # — a LITERAL rather than `1.year.ago`, for the reason given on `#holder` (fix wave — LOW-6).
  def annual(name, amount:, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(
        :budget,
        category: category,
        amount: amount,
        interval_months: 12,
        rule_type: :bill,
        anchor_date: Date.current + 40.days,
        created_at: a_year_before_the_travelled_day.in_time_zone
      )
    end
  end

  # THE AUGUST GRID THE DATED EXAMPLES SHARE: biweekly anchored Aug 14 2026, so this period is
  # Aug 14–27 and every one of them travels to Aug 20. The rule is born on the boundary it accrues
  # from, so §3.2's walk visits ONE period and every figure is `target ÷ periods_left`.
  def due_on_the_august_grid(name, amount:, due:)
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    accumulating(
      name,
      amount: amount,
      due: due,
      funded_since: Date.new(2026, 8, 14),
      created_at: Time.zone.local(2026, 8, 14)
    )
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # WHAT PUTS MONEY BEHIND A RULE: the rule itself (it accrues) or a DATED ADJUSTMENT (§3.3). There
  # are no allocations — a claim is computed, and nothing moves.
  def set_aside(category, amount, on: Date.current)
    create(:adjustment, rule: category.budgets.first, amount: amount, date: on)
  end

  def spend(category, amount, on: Date.current)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # ── THE FIGURES AND THE BARS ───────────────────────────────────────────────────────────────────

  # THE SPEC'S OWN ROW, PLANTED BOTH DIRECTIONS: a $400 rate rule with $310 spent leaves $90 — which
  # the band this replaced printed as "$90.00 left". Both ends of the same subtraction are asserted,
  # so a section that printed the claim where the spending goes fails rather than looking plausible.
  it "prints spent of the rate for a budgeted category", :aggregate_failures do
    deposit(1_000)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 310)

    visit root_path

    expect(figure("Groceries")).to have_content("$310.00 of $400.00")
    expect(figure("Groceries")).to have_no_content("$90.00")
    expect(rule_row("Groceries")).to have_css("[data-rule-bar='78']")
  end

  # THE OTHER DIRECTION OF THE SAME FIGURE, on a category nobody has spent from: the numerator is the
  # spending and NOT the rate, so an untouched envelope reads $0 rather than its whole plan.
  it "reads zero spent on a budgeted category nobody has spent from", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(figure("Groceries")).to have_content("$0.00 of $400.00")
    expect(rule_row("Groceries")).to have_css("[data-rule-bar='0']")
  end

  # THE OVER STATE (§3): red figure, red bar, and the block's header tinted. $180 spent against a
  # $150 rate — the same fixture the categories band asserted as `overdrawn $80.00`.
  #
  # ** THE EXCESS ITSELF IS NAMED BY THE TROUBLE STRIP AND NOT BY THE ROW (§3's column list). ** The
  # clause under a row is the DAY: what resets when, what is due when. "over by $30.00" is one of
  # §5's two per-rule triggers, it is printed inches above by `_trouble.html.erb`, and the figure
  # here says the same thing in the numbers it is over BY.
  it "turns the figure and the bar red when the rule is spent past its rate", :aggregate_failures do
    deposit(200)
    dining = envelope("Dining Out", rate: 150)
    spend(dining, 180)

    visit root_path

    expect(figure("Dining Out")).to have_content("$180.00 of $150.00")
    expect(figure("Dining Out")[:class]).to include("text-status-danger")
    expect(rule_row("Dining Out")).to have_css("[data-rule-bar='100'][data-rule-bar-state='over']")
    expect(rule_row("Dining Out")).to have_css("[data-rule-fill].bg-status-danger")
    expect(header("Dining Out")[:class]).to include("bg-status-danger-light")
  end

  # THE OTHER DIRECTION, on a category that spent to the penny: exactly the plan is the tidiest
  # outcome there is, and reading it as trouble would be the same lie as `-$0.00`. The bar is FULL —
  # green, arrived — which is the state §3 gives it, and the header is not tinted.
  it "calls a rule that spent exactly its rate full rather than over", :aggregate_failures do
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 400)

    visit root_path

    expect(figure("Groceries")).to have_content("$400.00 of $400.00")
    expect(figure("Groceries")[:class]).not_to include("text-status-danger")
    expect(rule_row("Groceries")).to have_css("[data-rule-bar-state='full']")
    expect(rule_row("Groceries")).to have_css("[data-rule-fill].bg-status-success")
    expect(header("Groceries")[:class]).not_to include("bg-status-danger-light")
  end

  # ** THE WINDOW IS THIS PERIOD AND NOT ALL TIME. ** Two receipts on one category, one inside the
  # period and one before it opened. The bar counts the first and not the second.
  it "counts only the spending inside this period", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    groceries = envelope("Groceries", rate: 400)
    deposit(1_000)
    spend(groceries, 310, on: Date.new(2026, 8, 20))
    spend(groceries, 50, on: Date.new(2026, 8, 10))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Groceries")).to have_content("$310.00 of $400.00")
    expect(figure("Groceries")).to have_no_content("$360.00")
  end

  # SAVINGS GOALS KEEP THEIR TARGET BARS (answers-first §4), and the figure is what is BUILT UP
  # rather than what was spent — the word "left" must stay off it for the reason that state exists at
  # all, and so must "spent", which is what a target's running total is not.
  #
  # ** THE $424 IS AN ACCRUAL AND AN ADJUSTMENT (§3.3). ** PLANTED: a $2,400 goal six fortnights out,
  # so §3.2's first period plans `2,400 ÷ 6` = $400, plus a dated `+$24` set-aside, capped at the
  # target and with nothing spent — `built_up` is **$424.00** and the bar is
  # `round(424 ÷ 2,400 × 100)` = **18%**. Unchanged from the allocation era; only the two words went.
  it "keeps a savings goal's target bar", :aggregate_failures do
    deposit(500)
    set_aside(goal("Vacation", target: 2_400, periods: 6), 24)

    visit root_path

    expect(figure("Vacation")).to have_content("$424.00 of $2,400.00")
    expect(figure("Vacation")).to have_no_content("built up")
    expect(rule_row("Vacation")).to have_no_content("left")
    expect(rule_row("Vacation")).to have_no_content("spent")
    expect(rule_row("Vacation")).to have_css("[data-rule-bar='18']")
  end

  # ** WHAT A GOAL SAYS ABOUT TIME IS THE DAY AND WHAT THIS PERIOD IS PUTTING IN. ** It read
  # `next due <date> · $200.00 per period`; the clause is `<date> · +$200.00` now, and the PLUS is
  # what tells a contribution from a total. PLANTED: a $5,000 goal twenty-five fortnights out,
  # written today, so the walk visits one period — `planned = 5,000 ÷ 25` = **$200.00**, the bar is
  # `round(200 ÷ 5,000 × 100)` = **4%**, and the day is far outside this period, so nothing about it
  # is short.
  it "says what a goal adds this period, beside the day it is needed", :aggregate_failures do
    deposit(500)
    goal("Vacation", target: 5_000, periods: 25)

    visit root_path

    expect(figure("Vacation")).to have_content("$200.00 of $5,000.00")
    expect(when_clause("Vacation")).to have_content("+$200.00")
    expect(rule_row("Vacation")).to have_no_content("overdue")
    expect(rule_row("Vacation")).to have_no_content("short")
    expect(rule_row("Vacation")).to have_css("[data-rule-bar='4']")
  end

  # ** AN ANCHOR-DATED RULE READS TOWARD ITS OWN AMOUNT (§3's shape rule). ** PLANTED on the fixed
  # grid so no figure moves with the wall clock: a $300 bill due Oct 9, `periods_left` 5, so
  # `planned = 300 ÷ 5` = **$60.00** and one walked period leaves `built_up` at **$60.00**.
  it "reads an anchor-dated rule by the day and its share", :aggregate_failures do
    on_the_fixed_grid("House Deposit", amount: 300)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("House Deposit")).to have_content("$60.00 of $300.00")
    expect(when_clause("House Deposit")).to have_content("Oct 9 · +$60.00")
  end

  # ** A PAID ONE-OFF SAYS `paid <date>`, WHERE IT WENT ON PROMISING A BILL THAT WAS DONE
  # (two-shapes Task 3's carry (a)). ** A one-time bill's occurrence NEVER rolls, so after the money
  # went out the row kept reading `Aug 24 · ready` until the date passed and `overdue · was Aug 24`
  # for ever afterwards — two sentences about a bill nobody owed any more, and the second is the one
  # the trouble strip fired on. The fulfilment is the fact (`ClaimCalculator#settled?`), and the day is the day the
  # spending reached the target.
  #
  # BOTH DIRECTIONS ON ONE FIXTURE: the same rule before and after the payment, which is what says
  # the arm fires on the payment rather than on the date.
  it "calls a paid one-off paid, with the day the money went out", :aggregate_failures do
    water = one_off_bill_on_the_fixed_grid

    # BEFORE THE PAYMENT the fund has caught up — `periods_left` from Aug 14 to Aug 24 is one, so
    # §3.2 asks the whole $600 in the walked period — and the row reads READY, which is the
    # ordinary shape of a bill due inside this period with its money set aside. What matters is that
    # the same row does NOT go on saying it after the money has gone out.
    travel_to(Date.new(2026, 8, 20)) { visit root_path }
    expect(when_clause("Utilities", lane: "Water")).to have_content("Aug 24 · ready")

    create(:entry, item: water, amount: 600, date: Date.new(2026, 8, 18))
    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(when_clause("Utilities", lane: "Water")).to have_content("paid Aug 18")
    expect(rule_row("Utilities", lane: "Water")).to have_no_content("ready")
    expect(rule_row("Utilities", lane: "Water")).to have_no_content("overdue")
  end

  # ── THE CLAUSE, WHICH IS THE DAY (§3) ─────────────────────────────────────────────────────────

  # ** `on track` IS DELETED AND THE DAY IS WHAT REPLACES IT. ** That clause was `HoldingStatus`'s
  # word for "this category holds what the rule has asked for so far", and there is no holding to
  # compare an ask against. PLANTED on the fixed grid: a $2,000 bill due Oct 9, `periods_left` 5, so
  # `planned = 2,000 ÷ 5` = **$400.00** and one walked period leaves `built_up` at **$400.00**.
  it "gives an accruing row the day and its share", :aggregate_failures do
    deposit(2_000)
    on_the_fixed_grid("Rent", amount: 2_000)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Rent")).to have_content("$400.00 of $2,000.00")
    expect(when_clause("Rent")).to have_content("Oct 9 · +$400.00")
    expect(when_clause("Rent")).to have_no_content("on track")
  end

  # ** A RATE ROW GAINS A CLAUSE IT NEVER HAD, AND "leaves the clause off a quiet envelope" IS
  # DELETED FOR IT. ** That example asserted no element at all, on the argument that "left to spend"
  # IS the bar said backwards. The clause is not a status any more: it is the DAY, and a
  # use-it-or-lose-it rule's day is the boundary it starts again on (§3.1) — the one fact its figure
  # and its bar cannot say. "left" still must not appear, which is the half of the old example that
  # was about the words.
  #
  # Aug 14 – Aug 27 is this period on the planted grid, so the rate resets on **Aug 28**.
  it "says when a quiet envelope starts again", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 100, on: Date.new(2026, 8, 20))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Groceries")).to have_content("$100.00 of $400.00")
    expect(when_clause("Groceries")).to have_content("resets Aug 28")
    expect(rule_row("Groceries")).to have_no_content("left")
  end

  # ** THE MONEY IS NOT THERE FOR A DAY THAT IS (§3), which is the state the runway's red tick fires
  # on and the widest of the header tint's three causes. ** PLANTED on a grid whose period is
  # Aug 14–27: a $120 bill due **Aug 24** — inside it — with a −$40 adjustment taking the catch-up's
  # $120 down to **$80**, so the gap is $40. Nothing has gone wrong (no date has passed, nothing was
  # overspent), so §5's strip stays silent while the block tints.
  it "names the gap on a rule whose day is inside this period", :aggregate_failures do
    deposit(1_000)
    utilities = due_on_the_august_grid("Utilities", amount: 120, due: Date.new(2026, 8, 24))
    set_aside(utilities, -40, on: Date.new(2026, 8, 20))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Utilities")).to have_content("$80.00 of $120.00")
    expect(when_clause("Utilities")).to have_content("Aug 24 · $40.00 short")
    expect(rule_row("Utilities")).to have_css("[data-rule-bar-state='short']")
    expect(header("Utilities")[:class]).to include("bg-status-danger-light")
    expect(page).to have_no_css("[data-trouble]")
  end

  # A DATE THAT WENT BY WITH THE MONEY NEVER SPENT (§3.2), in `#claim_trouble_label`'s exact wording
  # — the strip above and the row below print ONE string about one rule. PLANTED: a $600 bill
  # anchored Aug 15, walked from Aug 14, so the catch-up fills it and the day passes unpaid.
  it "puts a date already gone in the past tense", :aggregate_failures do
    deposit(1_000)
    due_on_the_august_grid("Insurance", amount: 600, due: Date.new(2026, 8, 15))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(when_clause("Insurance")).to have_content("overdue · was Aug 15")
    expect(header("Insurance")[:class]).to include("bg-status-danger-light")
  end

  # ── THE BLOCK ITSELF: THE HEADER, THE ROWS AND THE ORDER (§3) ─────────────────────────────────

  # ** A ROW PER RULE, NAMED BY ITS LANE, STRIPED BY ITS TYPE. ** The whole reason the section is
  # blocks: a category carrying a $400 usage envelope and a $60 choice rule on one of its items shows
  # both, in the order they would give way (choice first), each with its own colour — where the flat
  # row indented the second under the first and gave both the category's own ranking.
  #
  # THE HEADER ADDS THEM UP: $400 − $150 spent = $250 claimed on the catch-all lane, $60 on Treats,
  # so the header reads **$310.00 claimed** while neither row's figure is that number.
  it "gives a category a row per rule, in give-way order, and adds them up", :aggregate_failures do
    deposit(1_000)
    groceries = envelope("Groceries", rate: 400)
    second_rule(groceries, "Treats", rate: 60, type: :choice)
    spend(groceries, 150)

    visit root_path

    expect(header("Groceries")).to have_content("2 rules").and have_content("$310.00 claimed")
    expect(block("Groceries").all("[data-rule-row]").pluck("data-rule-row")).to eq(["Treats", "Whole category"])
    # THE STRIPE IS THE RULE'S TYPE AND NOT THE CATEGORY'S: one block, two colours.
    expect(rule_row("Groceries", lane: "Treats")).to have_css(".bg-terracotta")
    expect(rule_row("Groceries")).to have_css(".bg-dusty-teal")
  end

  # ** THE SHAPE CLAUSE, ONE PER SHAPE (§3). ** Three rules the user could actually write, each
  # saying itself back: an allowance, a repeating bill, and a figure by a day. The type is the first
  # word of every one of them, which is what the stripe beside it is a picture of.
  it "says each rule's shape in its own words", :aggregate_failures do
    deposit(2_000)
    envelope("Groceries", rate: 400)
    annual("Insurance", amount: 600, priority: 2)
    goal("Vacation", target: 5_000, periods: 25, priority: 3, type: :choice)

    visit root_path

    shapes = ["Groceries", "Insurance", "Vacation"].map { |name| rule_row(name).find("[data-rule-shape]").text }

    expect(shapes.first(2)).to eq(["usage · a period", "bill · every 12 months"])
    expect(shapes.last).to start_with("choice · $5,000.00 by")
  end

  # ** THE ORDER IS THE GIVE-WAY WALK, AND "sorts trouble first and keeps fill order behind it" IS
  # DELETED FOR IT. ** That example asserted a SECOND ordering — a category in trouble jumped the
  # queue — and there is only one now: the blocks are `#give_way_order` grouped back, the same walk
  # the trouble strip lists its shortfall in, so a category cannot rank one way in the strip and
  # another in the section. Trouble is the TINT (pinned above), which does not move anything.
  #
  # PLANTED so every term of the key decides something: a CHOICE rule leads whatever its priority, a
  # BILL is last whatever its priority, and between two usage rules the higher priority NUMBER — the
  # one that would be funded last — gives way first.
  it "orders the blocks by the rule of each that gives way first" do
    deposit(2_000)
    envelope("Rent", rate: 400, priority: 1, type: :bill)
    envelope("Groceries", rate: 400, priority: 2)
    envelope("Pet Care", rate: 100, priority: 3)
    envelope("Fun money", rate: 100, priority: 4, type: :choice)

    visit root_path

    expect(section.text).to match(/Fun money.*Pet Care.*Groceries.*Rent/m)
  end

  # THE HEADING COUNTS WHAT THE SECTION HOLDS, and the claimed total is `#total_claims` — THE SAME
  # figure the money column subtracts from checking, which is why a block-by-block sum that had
  # drifted would show up here rather than nowhere.
  #
  # ** THE DAYS-LEFT CLAUSE IS DELETED FROM THIS HEADING (§3). ** It was printed here AND under the
  # hero's bar, by two readers that could disagree; the period is the runway's subject now, and
  # `runway_spec.rb` carries "7 days left" with the ruler it belongs to.
  it "heads the section with what it holds and what it claims", :aggregate_failures do
    deposit(2_000)
    second_rule(envelope("Groceries", rate: 400), "Treats", rate: 60)
    envelope("Rent", rate: 900, priority: 2, type: :bill)

    visit root_path

    expect(find("[data-this-period-heading]")).to have_content("This period · 2 categories · 3 rules")
    expect(find("[data-this-period-heading]")).to have_no_content("days left")
    expect(find("[data-this-period-claimed]")).to have_content("$1,360.00 claimed")
  end

  # ** THE GIVE-WAY SENTENCE (§3's "below"), WHICH IS THE ORDER ABOVE SAID IN WORDS. ** An order
  # nobody explains reads as arbitrary; the three words are the app's own and the door is the page
  # where the order is changed.
  it "says which rules give way first, under the blocks", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(find("[data-give-way]")).to have_content("choices give way first, then usage, and bills last")
    expect(find("[data-give-way]"))
      .to have_link("Change what a category asks for on the Budget page", href: budget_page_path)
  end

  # ── CATEGORIES NO RULE CLAIMS (answers-first §4) ──────────────────────────────────────────────

  # THE FACT, NO BAR, NO PRESSURE. A category nobody budgeted has nothing for a bar to be a fraction
  # of — no rule claims its receipts — so inventing a denominator would be inventing the pressure.
  it "names an unbudgeted category with spending, and gives it no bar", :aggregate_failures do
    subscriptions = create(:category, :expense, user: user, name: "Subscriptions")
    create(:entry, item: create(:item, category: subscriptions), amount: 32, date: Date.current)

    visit root_path

    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_content("spent $32.00")
    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_no_css("[data-rule-bar]", visible: :all)
    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_no_content(" of ")
  end

  # THE ABSENCE CASE, and it is the half a positive-only file would never measure: an unbudgeted
  # category the user has not spent from this period is not on Home at all.
  it "leaves a zero-spend unbudgeted category off the section entirely", :aggregate_failures do
    create(:category, :expense, user: user, name: "Someday")
    spender = create(:category, :expense, user: user, name: "Subscriptions")
    create(:entry, item: create(:item, category: spender), amount: 32, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-unbudgeted-row='Subscriptions']")
    expect(page).to have_no_css("[data-unbudgeted-row='Someday']")
    expect(section).to have_no_content("Someday")
  end

  # The window applies to these rows too, and this is the direction that catches a query bounded on
  # the wrong side: spending from a PREVIOUS period leaves the category off entirely rather than
  # listing it at last period's figure.
  it "leaves an unbudgeted category off when its spending was in a previous period", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    stale = create(:category, :expense, user: user, name: "Old Subscriptions")
    create(:entry, item: create(:item, category: stale), amount: 32, date: Date.new(2026, 8, 10))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(page).to have_no_css("[data-unbudgeted-row='Old Subscriptions']")
  end

  # ** A FUNDED HOLDER WITH NO RULE IS THE SAME ROW NOW (§3). ** It used to be a BUDGETED row with an
  # empty line list, printing `spent $45.00` from one reader while an unfunded category printed the
  # same string from another; they are one fact — no rule claims these receipts — so there is one
  # row type. With spending it states the fact; without it, it is absent.
  it "states a rule-less holder's spending as the same row, and drops it when there is none", :aggregate_failures do
    spend(holder("Car Repairs", priority: 1), 45)
    holder("Someday Fund", priority: 2)

    visit root_path

    expect(find("[data-unbudgeted-row='Car Repairs']")).to have_content("spent $45.00")
    expect(page).to have_no_css("[data-category-block='Car Repairs']")
    expect(page).to have_no_css("[data-unbudgeted-row='Someday Fund']")
  end

  # ── THE EMPTY STATE AND THE DEAD WORDS ────────────────────────────────────────────────────────

  # A blank panel on a money screen reads as something that failed to load, and the door is the
  # Budget page — where a rule, the thing that gives a category a claim, is written.
  it "says so plainly when nothing has a rule and nothing was spent", :aggregate_failures do
    deposit(400)
    create(:category, :expense, user: user, name: "Someday")

    visit root_path

    expect(section).to have_content("Nothing is budgeted yet")
    expect(section).to have_link("Give a category a rule on the Budget page", href: budget_page_path)
    expect(section).to have_no_content("Someday")
  end

  # THE WORDS HOME NO LONGER SAYS (spec §3 and the plan's global constraints), scoped to this
  # section. CASE-INSENSITIVE, deliberately: `have_no_content("available")` is a substring match on
  # the rendered text, so it passes over a section printing "Available" — which is exactly the
  # spelling this app uses for the word, and therefore exactly the spelling that could slip in.
  #
  # ** "goal", "fund" AND "builds up" JOIN THE LIST WITH THE TWO SHAPES (§7). ** A goal IS a dated
  # rule; the section says its target and its day, which is what the user wrote.
  it "says none of the machinery words, in any casing", :aggregate_failures do
    deposit(1_000)
    spend(envelope("Groceries", rate: 400), 100)
    goal("Vacation", target: 5_000, periods: 25, priority: 2, type: :choice)

    visit root_path

    [/available/i, /unclaimed/i, /buffer/i, /set aside/i, /builds up/i].each do |word|
      expect(section).to have_no_content(word)
    end
  end

  # ── THE TWO COLUMNS, AND THE NARROW BREAKPOINT (§3) ───────────────────────────────────────────

  # TWO COLUMNS FROM 1024px: the driver's window is 1400 wide, so two blocks share a row. Measured on
  # the blocks' own rects rather than asserted from the classes, because a `grid-cols-2` that is
  # never reached by its breakpoint is a class that reads correct and renders one column.
  it "sets two blocks side by side on a wide screen", :aggregate_failures do
    deposit(2_000)
    envelope("Fun money", rate: 100, priority: 1, type: :choice)
    envelope("Pet Care", rate: 100, priority: 2)

    visit root_path

    first = block("Fun money").native.rect
    second = block("Pet Care").native.rect

    expect(second.y).to eq(first.y)
    expect(second.x).to be > first.x
  end

  # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE — Chrome refuses a headless
  # window narrower than 500px, so every `resize_to(375, …)` in this suite is really a 500px test.
  # `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is what CSS media queries
  # read. The mechanism is `money_spec.rb`'s, copied deliberately rather than re-derived.
  #
  # NO `evaluate_script` ANYWHERE IN THESE EXAMPLES, for that file's measured reason: a trailing JS
  # call leaves the session in a state Capybara's teardown navigation does not survive, which
  # surfaces as `InvalidSessionIdError` with zero assertion failures.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # ONE COLUMN, AND THE ROWS DROP THE BAR (§3). The bar is the least of what a row says — the
    # figure beside it is the same fact in numbers — and it is the first thing to cost more width
    # than it earns. Both halves are measured: the second block sits BELOW the first, and the bar is
    # not rendered visible at all.
    it "stacks the blocks and drops the bars inside a 375px viewport", :aggregate_failures do
      deposit(2_000)
      spend(envelope("Fun money", rate: 100, priority: 1, type: :choice), 40)
      envelope("Pet Care", rate: 100, priority: 2)

      visit root_path

      expect(figure("Fun money")).to have_content("$40.00 of $100.00")
      expect(rule_row("Fun money")).to have_no_css("[data-rule-bar]")

      first = block("Fun money").native.rect
      second = block("Pet Care").native.rect

      expect(second.y).to be > first.y
      expect(second.x + second.width).to be <= 375
    end

    # ** THE ACCRUING ROW IS THE WIDEST SENTENCE THIS SECTION PRINTS ** — a six-figure amount, a
    # target, and a shape clause naming a date — so it is measured rather than assumed to inherit the
    # rate row's fit. PLANTED: a $5,000 goal twenty-five fortnights out with a $1,034.56 set-aside on
    # top of its $200 share = **$1,234.56**.
    it "fits a goal's figure and its clauses inside a 375px viewport", :aggregate_failures do
      deposit(2_000)
      vacation = goal("Vacation", target: 5_000, periods: 25, type: :choice)
      set_aside(vacation, 1_034.56)

      visit root_path

      expect(figure("Vacation")).to have_content("$1,234.56 of $5,000.00")
      expect(rule_row("Vacation").find("[data-rule-shape]")).to have_content("choice · $5,000.00 by")

      panel = page.find("[data-this-period]").native.rect
      amount = figure("Vacation").native.rect

      expect(panel.x + panel.width).to be <= 375
      expect(amount.x + amount.width).to be <= panel.x + panel.width
    end
  end
end
