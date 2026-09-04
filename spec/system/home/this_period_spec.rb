# frozen_string_literal: true

require "rails_helper"

# HOME'S "THIS PERIOD" SECTION — spending as progress (answers-first spec §4). This file is
# `spec/system/home/categories_spec.rb`'s successor.
#
# ** THE INVERSE OF THE BAND IT REPLACES. ** The categories band printed `$90.00 left` off
# `HoldingStatus#amount`; this section prints `$310.00 of $400.00`, which is the same $90 said from
# the other end. Every figure carried below is the figure the categories-band example asserted, in
# the inverted shape — a bar that stopped subtracting fails here rather than agreeing with itself.
#
# ** AND THE FIGURES ARE CLAIMS NOW (computed-claims Task 3). ** Nothing is allocated into a category
# any more (§5), so every `fund(...)` in this file is gone and the money that was moved is written the
# way the model actually puts it there: a rule that accrues, or a dated adjustment (§3.3). The
# spent-of-rate figures did not move at all — spending was never an allocation — and the two rows that
# read a HOLDING (the goal's $424, the anchor-dated goal) are re-derived from §3's formulas with the
# working beside them. Two examples are DELETED rather than converted, each named at its own site.
#
# ── CARRIED FROM categories_spec.rb (figures preserved, presentation inverted):
#
#   * "heads the band with available and the accounts with their own balances" → split: the
#     three-figures-from-three-moments half is the hero's and stays in `hero_spec`; the row half is
#     "prints spent of planned for a budgeted category", $100 held of a $400 rule → `$300.00 of
#     $400.00`.
#   * "shows a savings goal saving toward its target, never as money to spend" → "keeps a savings
#     goal's target bar", the same $424 of $2,400.
#   * "reads an anchor-dated goal by its schedule rather than as saving" → carried with ONE stated
#     correction: the target figure is now ON the row (the bar is drawn at the CHROME level of the
#     app's two-level goal classification, where a goal is a goal whatever refills it), so the
#     assertion moves to the CLAUSE, which is where the old example's point actually lived.
#   * "shows a balance on an on-track category" → "keeps the status vocabulary as a small clause",
#     the same $2,000 Rent.
#   * "explains an overdrawn rate category by its rate" / "says so plainly when an overdrawn
#     category has no rules at all" → the rule detail they assert moved to the trouble strip with
#     the auto-expand; see `trouble_spec.rb`. Their SPENDING figures are carried here as the over
#     state ($180 spent of a $150 rate).
#   * "marks a rate category whose period has ended, and only that one" → DELETED at the body, with
#     the ` · last period` suffix it asserted (computed-claims Task 3); the reason is written there.
#   * "says so plainly when no category holds money yet" → carried, with the section's own copy.
#   * "a quiet category's due date" (both examples) → carried as "an accruing row's clause": the date
#     rides on §3.4's schedule line now, and what displaces it is the claim's own trouble label.
#   * the "changed a rule after distributing" group → DELETED with the distribution (Task 3). The
#     clause compared a category's rules against the moment its last split was written; there is no
#     split.
#
# ── MOVED, NOT DELETED — the rule detail and the account cards found new homes:
#
#   * "shows an overdue category with the date that passed and the rule behind it", "shows a behind
#     category with the rule it is behind on", "explains an overdrawn rate category by its rate",
#     "says so plainly when an overdrawn category has no rules at all" → `trouble_spec.rb`. The rules
#     they assert now render under the strip's own rows, which is where the auto-expand rule
#     ("anything needing attention opens itself") describes the whole population.
#   * "names an overdrawn account's balance as the debt it is" → `accounts_spec.rb`, at the same
#     -$400.00: the account cards are inside the accounts line's expansion now (spec §6).
#
# ── DELETED WITH THE CATEGORIES BAND (four titles):
#
#   * "keeps the categories out of the accounts band" — there is no accounts band; `accounts_spec.rb`
#     owns what the one collapsed line does and does not contain.
#   * "auto-expands a category that needs attention", "leaves a quiet category collapsed" and
#     "expands only the rows that need attention" — `data-expanded` is gone with `_holding_row`. A
#     row that needs attention is IN the trouble strip, with its rules under it, and one that does
#     not is not; the chevron had nothing left to hide.
#
# EVERY COPY ASSERTION IN THIS FILE GOES THROUGH A DATA HOOK — `[data-this-period]`,
# `[data-period-row]`, `[data-period-figure]`, `[data-period-bar]`, `[data-period-clause]`,
# `[data-unbudgeted-row]`.
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

  def row(name) = find("[data-period-row='#{name}']")

  def figure(name) = find("[data-period-row='#{name}'] [data-period-figure]")

  def clause(name) = find("[data-period-row='#{name}'] [data-period-clause]")

  # A CATEGORY THAT HOLDS MONEY (spec §3): an expense category with a `funded_since`. A year back,
  # so every entry and allocation this file dates "today" counts against it.
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

  # A rate category: refilled every period, and the shape whose plan is its rate.
  def envelope(name, rate:, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: rate)
    end
  end

  # A bill that accrues toward a date (computed-claims §3.2) — the shape whose row reads
  # `built up of target · next due · $X per period`.
  #
  # `created_at:` IS PLANTED WHEREVER THE WALK HAS TO REACH BACK (the ruling of 2026-09-03): a rule
  # accrues from the LATER of its category's `funded_since` and its own birthday, so a rule the
  # factory writes at real-now walks nothing at all inside a `travel_to` that has gone backwards.
  # Omitted where the example's `today` is the real one, which is every example without a `travel_to`.
  def accumulating(name, amount:, due:, priority: 1, **plant)
    rule = plant.extract!(:created_at)
    holder(name, priority: priority, **plant).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: 1, anchor_date: due, **rule)
    end
  end

  # THE FIXED GRID THREE EXAMPLES BELOW SHARE: biweekly anchored Aug 14 2026, `today` Aug 20, and a
  # rule born on that boundary so §3.2's walk opens there and every figure they plant is derivable.
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

  # A GOAL IS A RULE WITH A TARGET (computed-claims §3.2), and a goal fed only by hand is a rule with
  # a target and an amount of ZERO — "no rate" spelled as a figure, because every claim comes from a
  # rule and zero is the only honest way to say a rule has no standing contribution.
  #
  # ** THE RULE CARRIES BOTH COLUMNS NOW (rules-own-the-budget spec §2.1 row 4): `carries_over` is
  # what makes the money build up and `target_amount` is where it stops. ** The CATEGORY keeps its
  # copy of the figure because the screens that read it have not been moved yet; the claim formulas
  # read only the rule.
  def goal(name, target:, priority: 1)
    holder(name, priority: priority, target_amount: target).tap do |category|
      create(:budget, :hand_fed, category: category, target_amount: target)
    end
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # ** `fund` IS DELETED (computed-claims Task 3), AND WITH IT EVERY `create(:allocation, …)` IN THIS
  # FILE. ** An allocation was money MOVED into a category; a claim is computed from the rule, the
  # calendar, the spending and the dated adjustments (§3), so an allocation moves no figure on this
  # screen at all. Where an example needed money to BE in a category, it now writes what actually puts
  # it there: a rule that accrues, or a dated adjustment (§3.3).
  def set_aside(category, amount, on: Date.current)
    create(:adjustment, rule: category.budgets.first, amount: amount, date: on)
  end

  # SPENDING DRAINS THE CATEGORY and the pot at once.
  def spend(category, amount, on: Date.current)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # ── THE BARS (spec §4) ─────────────────────────────────────────────────────────────────────────

  # THE SPEC'S OWN ROW, PLANTED BOTH DIRECTIONS: a $400 rate rule funded in full and $310 spent
  # leaves $90 — which the band this replaced printed as "$90.00 left". Both ends of the same
  # subtraction are asserted, so a section that printed the holding where the spending goes (or the
  # rate where the holding goes) fails rather than looking plausible.
  it "prints spent of planned for a budgeted category", :aggregate_failures do
    deposit(1_000)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 310)

    visit root_path

    expect(figure("Groceries")).to have_content("$310.00 of $400.00")
    expect(figure("Groceries")).to have_no_content("$90.00")
    expect(row("Groceries")).to have_css("[data-period-bar='78']")
  end

  # THE OTHER DIRECTION OF THE SAME FIGURE, on a category nobody has spent from: the numerator is
  # the spending and NOT the rate, so an unfunded envelope reads $0 rather than its whole plan.
  it "reads zero spent on a budgeted category nobody has spent from", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(figure("Groceries")).to have_content("$0.00 of $400.00")
    expect(row("Groceries")).to have_css("[data-period-bar='0']")
  end

  # THE OVER STATE (spec §4): red bar and red figure. $180 spent against a $150 rate — the same
  # fixture the categories band asserted as `overdrawn $80.00`, which is still the clause beside it.
  it "turns the bar and the figure red when the category is spent past its plan", :aggregate_failures do
    deposit(200)
    dining = envelope("Dining Out", rate: 150)
    spend(dining, 180)

    visit root_path

    expect(figure("Dining Out")).to have_content("$180.00 of $150.00")
    expect(figure("Dining Out")[:class]).to include("text-status-danger")
    expect(row("Dining Out")).to have_css("[data-period-bar='100']")
    expect(row("Dining Out")).to have_css("[data-period-fill].bg-status-danger")
    expect(clause("Dining Out")).to have_content("over by $30.00")
  end

  # The other direction of the over state, on a category that spent to the penny: exactly the plan
  # is the tidiest outcome there is, and reading it as trouble would be the same lie as `-$0.00`.
  it "leaves a category that spent exactly its plan in the quiet colour", :aggregate_failures do
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 400)

    visit root_path

    expect(figure("Groceries")).to have_content("$400.00 of $400.00")
    expect(figure("Groceries")[:class]).not_to include("text-status-danger")
    expect(row("Groceries")).to have_no_css("[data-period-fill].bg-status-danger", visible: :all)
  end

  # ** THE WINDOW IS THIS PERIOD AND NOT ALL TIME. ** Two receipts on one category, one inside the
  # period and one before it opened. The bar counts the first and not the second — which is the
  # whole difference between "spent this period" and the calculator's cumulative expense term.
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
  # rather than what was spent: "$424.00 of $2,400.00" is the row the categories band printed, at the
  # same two figures, and the word "left" must stay off it for the reason that state exists at all.
  #
  # ** THE $424 IS AN ADJUSTMENT NOW, NOT AN ALLOCATION (computed-claims §3.3). ** A goal fed by hand
  # is a zero-amount rule with a target, and a set-aside is a dated `+$424` on it. PLANTED: §3.2's
  # walk over one period — `planned = min(rate 0, gap 2,400) = 0`, `accrued = 0 + 424`, capped at the
  # target and with nothing spent — so `built_up` is **$424.00** and the bar is
  # `round(424 / 2,400 × 100)` = **18%**, both unchanged from the allocation era.
  it "keeps a savings goal's target bar", :aggregate_failures do
    deposit(500)
    set_aside(goal("Vacation", target: 2_400), 424)

    visit root_path

    expect(figure("Vacation")).to have_content("$424.00 built up of $2,400.00")
    expect(row("Vacation")).to have_no_content("left")
    expect(row("Vacation")).to have_no_content("spent")
    expect(row("Vacation")).to have_css("[data-period-bar='18']")
  end

  # ** AN ANCHOR-DATED GOAL READS BY ITS SCHEDULE, AND THE ANCHOR WINS OVER THE TARGET (§3's shape
  # rule). ** The categories band's version of this example asserted `have_no_content("of $2,400.00")`
  # on the whole row, because an anchor-dated goal's status was its schedule rather than `saving`. The
  # computed model makes that structural rather than a matter of wording: a rule with an anchor is
  # DATED, and a dated rule accrues toward ITS OWN amount by ITS OWN deadline — the category's $2,400
  # target belongs to whatever rule has no anchor, and this row never mentions it.
  #
  # PLANTED, on a fixed grid so no figure here moves with the wall clock. Biweekly anchored Aug 14
  # 2026, `today` Aug 20, the rule born on the boundary it accrues from, a $300 bill due Oct 9.
  # §3.2's catch-up: `periods_left` counts the boundaries from Aug 14 through Oct 9 inclusive —
  # Aug 14, Aug 28, Sep 11, Sep 25, Oct 9 = **5** — so `planned = 300 ÷ 5` = **$60.00**, one period is
  # walked, and `built_up` is **$60.00**.
  it "reads an anchor-dated goal by its schedule, toward the bill and not the target", :aggregate_failures do
    on_the_fixed_grid("House Deposit", amount: 300).update!(target_amount: 2_400)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("House Deposit")).to have_content("$60.00 built up of $300.00")
    expect(clause("House Deposit")).to have_content("next due Oct 9 · $60.00 per period")
    expect(row("House Deposit")).to have_no_content("$2,400.00")
  end

  # ── THE CLAUSE (spec §4: the status vocabulary "where it earns its place") ─────────────────────

  # ** `on track` IS DELETED, AND THE SCHEDULE IS WHAT REPLACES IT (computed-claims Task 3). ** The
  # old clause was `HoldingStatus`'s word for "this category holds what the rule has asked for so
  # far", and there is no holding to compare an ask against. §3.4 gives the accruing row its own
  # second line instead — `next due Mar 1 · $200.00 per period` — which says the same thing with the
  # two facts that make it checkable rather than with a verdict.
  #
  # PLANTED, on the same fixed grid: biweekly anchored Aug 14 2026, `today` Aug 20, a $2,000 bill due
  # Oct 9, the rule born Aug 14. `periods_left` = 5 (Aug 14 … Oct 9), so `planned = 2,000 ÷ 5` =
  # **$400.00** and one walked period leaves `built_up` at **$400.00**.
  it "gives an accruing row the schedule as its clause", :aggregate_failures do
    deposit(2_000)
    on_the_fixed_grid("Rent", amount: 2_000)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Rent")).to have_content("$400.00 built up of $2,000.00")
    expect(clause("Rent")).to have_content("next due Oct 9 · $400.00 per period")
    expect(clause("Rent")).to have_no_content("on track")
  end

  # NO CLAUSE ON A ROW THAT HAS NOTHING TO ADD. `left to spend` IS the bar, said backwards, so
  # printing it beside the bar would be the app answering one question twice.
  it "leaves the clause off a quiet envelope", :aggregate_failures do
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    spend(groceries, 100)

    visit root_path

    expect(figure("Groceries")).to have_content("$100.00 of $400.00")
    expect(row("Groceries")).to have_no_css("[data-period-clause]")
    expect(row("Groceries")).to have_no_content("left")
  end

  # ** "marks a rate category whose period has ended, and only that one" IS DELETED (computed-claims
  # Task 3), with the ` · last period` suffix it asserted. ** That suffix said "this money belongs to
  # a period that has closed, and the next distribution will sweep it back" — a fact about ALLOCATED
  # money awaiting a movement. A rate claim is use-it-or-lose-it and resets at the boundary by
  # definition (§3.1): there is no leftover to belong to a past period and nothing to sweep. Its
  # fixture helper `overspend_on_both_sides_of_a_boundary` goes with it, and so does the
  # `changed_after_distributing` clause the file's header names — there is no distribution to have
  # changed a rule after.

  # CARRIED FROM "a quiet category's due date", and the question is the same one: does the row keep
  # the date that is the only thing its figure cannot say? What changed is which clause displaces it —
  # it used to be a status that needed attention, and it is now the claim's own trouble label.
  describe "an accruing row's clause" do
    # THE QUIET DIRECTION: the schedule, with the date on it. Same fixed grid; a $300 bill due Oct 9,
    # `periods_left` 5, so `planned = 300 ÷ 5` = **$60.00** and one walked period leaves $60 built up.
    it "prints the next due date while nothing is wrong", :aggregate_failures do
      on_the_fixed_grid("Old Goal", amount: 300)

      travel_to(Date.new(2026, 8, 20)) { visit root_path }

      expect(clause("Old Goal")).to have_content("next due Oct 9 · $60.00 per period")
    end

    # THE OTHER DIRECTION, on a rule that is over: the trouble label takes the clause, because that is
    # the news and a schedule beside it would bury it. PLANTED: a $150 rate rule with $180 spent —
    # `over by 180 − 150` = **$30.00** — and no date anywhere on the row, because a rate rule has none.
    it "gives the line to the trouble label where something is wrong", :aggregate_failures do
      dining = envelope("Dining Out", rate: 150)
      spend(dining, 180)

      visit root_path

      expect(clause("Dining Out")).to have_content("over by $30.00")
      expect(clause("Dining Out")).to have_no_content("next due")
    end
  end

  # ── UNBUDGETED CATEGORIES (spec §4) ────────────────────────────────────────────────────────────

  # THE FACT, NO BAR, NO PRESSURE. A category nobody budgeted has nothing for a bar to be a fraction
  # of — its receipts drain AVAILABLE — so inventing a denominator would be inventing the pressure.
  it "names an unbudgeted category with spending, and gives it no bar", :aggregate_failures do
    subscriptions = create(:category, :expense, user: user, name: "Subscriptions")
    create(:entry, item: create(:item, category: subscriptions), amount: 32, date: Date.current)

    visit root_path

    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_content("spent $32.00")
    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_no_css("[data-period-bar]", visible: :all)
    expect(find("[data-unbudgeted-row='Subscriptions']")).to have_no_content(" of ")
  end

  # THE ABSENCE CASE, and it is the half a positive-only file would never measure: an unbudgeted
  # category the user has not spent from this period is not on Home at all. The Categories page
  # remains the full index.
  it "leaves a zero-spend unbudgeted category off the section entirely", :aggregate_failures do
    create(:category, :expense, user: user, name: "Someday")
    spender = create(:category, :expense, user: user, name: "Subscriptions")
    create(:entry, item: create(:item, category: spender), amount: 32, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-unbudgeted-row='Subscriptions']")
    expect(page).to have_no_css("[data-unbudgeted-row='Someday']")
    expect(section).to have_no_content("Someday")
  end

  # The window applies to the unbudgeted rows too, and this is the direction that catches a query
  # bounded on the wrong side: spending from a PREVIOUS period leaves the category off entirely
  # rather than listing it at last period's figure.
  it "leaves an unbudgeted category off when its spending was in a previous period", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    stale = create(:category, :expense, user: user, name: "Old Subscriptions")
    create(:entry, item: create(:item, category: stale), amount: 32, date: Date.new(2026, 8, 10))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(page).to have_no_css("[data-unbudgeted-row='Old Subscriptions']")
  end

  # A HOLDER WITH NO PLAN IS THE BUDGETED SIDE OF THE SAME RULE. It has no rule and no target, so
  # there is nothing for a bar to be a fraction of; with spending it states the fact, and without it
  # is absent — `spent $0.00` under a name is a row that reports nothing.
  it "states a plan-less holder's spending, and drops it entirely when there is none", :aggregate_failures do
    spend(holder("Car Repairs", priority: 1), 45)
    holder("Someday Fund", priority: 2)

    visit root_path

    expect(figure("Car Repairs")).to have_content("spent $45.00")
    expect(row("Car Repairs")).to have_no_css("[data-period-bar]", visible: :all)
    expect(page).to have_no_css("[data-period-row='Someday Fund']")
  end

  # ── SORT, HEADER AND THE EMPTY STATE ───────────────────────────────────────────────────────────

  # TROUBLE FIRST, THEN FILL ORDER (spec §4). Three categories in fill order 1-2-3 with the THIRD in
  # trouble: it comes first, and the other two keep their order behind it. Either half alone passes
  # against a section that simply reversed the list.
  it "sorts trouble first and keeps fill order behind it" do
    deposit(2_000)
    envelope("Rent", rate: 400, priority: 1)
    envelope("Groceries", rate: 400, priority: 2)
    spend(envelope("Dining Out", rate: 150, priority: 3), 180)

    visit root_path

    expect(section.text).to match(/Dining Out.*Rent.*Groceries/m)
  end

  # THE HEADER IS THE HERO'S OWN PERIOD READER (spec §4), so the days-left figure on this section
  # and the one under the hero's bar cannot come from two different windows.
  it "heads the section with the days left in the period", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    envelope("Groceries", rate: 400)
    deposit(1_000)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(find("[data-this-period-heading]")).to have_content("This period · 7 days left")
  end

  # No declared period, no invented boundary — the same refusal the hero's bar makes about the same
  # reader. The heading still names the section, because the section still has rows.
  it "names the section without a days clause before a period is declared", :aggregate_failures do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Groceries", rate: 400)
    deposit(1_000)

    visit root_path

    expect(find("[data-this-period-heading]")).to have_content("This period")
    expect(find("[data-this-period-heading]")).to have_no_content("days left")
  end

  # CARRIED FROM "says so plainly when no category holds money yet". A blank panel on a money screen
  # reads as something that failed to load, and the door is the Budget page — where a rule, the
  # thing that starts a category holding money, is written.
  it "says so plainly when nothing has a plan and nothing was spent", :aggregate_failures do
    deposit(400)
    create(:category, :expense, user: user, name: "Someday")

    visit root_path

    expect(section).to have_content("Nothing is budgeted yet")
    expect(section).to have_link("Give a category a rule on the Budget page", href: budget_page_path)
    expect(section).to have_no_content("Someday")
  end

  # THE WORDS HOME NO LONGER SAYS (spec §3), scoped to this section: the band it replaced headed
  # itself "available now" and the machinery words went with it.
  # CASE-INSENSITIVE, deliberately: `have_no_content("available")` is a substring match on the
  # rendered text, so it passes over a section printing "Available" — which is exactly the spelling
  # this app uses for the word (`ReallocationPresenter::Root#name`, the fix button's source), and
  # therefore exactly the spelling that could slip in here. A regexp with `/i` is the only form that
  # measures the rule the spec states.
  it "says none of the machinery words, in any casing", :aggregate_failures do
    deposit(1_000)
    spend(envelope("Groceries", rate: 400), 100)

    visit root_path

    expect(section).to have_no_content(/available/i)
    expect(section).to have_no_content(/unclaimed/i)
    expect(section).to have_no_content(/buffer/i)
  end

  # ── THE NARROW BREAKPOINT (spec §9: "hero and bars at 375px") ──────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE — Chrome refuses a headless
  # window narrower than 500px, so every `resize_to(375, …)` in this suite is really a 500px test.
  # `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is what CSS media queries
  # read. The mechanism is `hero_spec.rb`'s, copied deliberately rather than re-derived.
  #
  # NO `evaluate_script` ANYWHERE IN THE EXAMPLE, for `hero_spec`'s measured reason: a trailing JS
  # call leaves the session in a state Capybara's teardown navigation does not survive, which
  # surfaces as `InvalidSessionIdError` with zero assertion failures. Selenium's own geometry says
  # the thing this example is about — the section's right edge inside the viewport, and the widest
  # figure on it inside the section — without running a line of JS.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    it "fits a bar and its figures inside a 375px viewport", :aggregate_failures do
      deposit(2_000)
      groceries = envelope("Groceries", rate: 1_500)
      spend(groceries, 1_234.56)

      visit root_path

      expect(figure("Groceries")).to have_content("$1,234.56 of $1,500.00")

      panel = page.find("[data-this-period]").native.rect
      amount = page.find("[data-period-row='Groceries'] [data-period-figure]").native.rect

      expect(panel.x + panel.width).to be <= 375
      expect(amount.x + amount.width).to be <= panel.x + panel.width
    end
  end
end
