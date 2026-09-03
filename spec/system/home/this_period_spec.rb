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
#   * "marks a rate category whose period has ended, and only that one" → carried whole: the
#     ` · last period` suffix rides on the clause.
#   * "says so plainly when no category holds money yet" → carried, with the section's own copy.
#   * "a quiet category's due date" (both examples) → carried: the date clause rides on
#     `HomeHelper#period_row_clause`, which is `HomePresenter::Row#due_marker?`'s rule re-housed.
#   * the "changed a rule after distributing" group → its clause is asserted here on the row and in
#     the strip in `trouble_spec.rb`; the group's own fixtures live in `trouble_spec.rb`, which is
#     where the two-places-one-sentence pin belongs now that the strip is the other place.
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

  # A bill that accumulates toward a date — the shape that reads `on track` while it is on schedule.
  def accumulating(name, amount:, due:, priority: 1, every: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: every, anchor_date: due)
    end
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # MONEY INTO A CATEGORY IS AN ALLOCATION OUT OF AVAILABLE, and it moves nothing physical (§2).
  def fund(category, amount, on: Time.zone.now)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
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
    fund(groceries, 400)
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
    fund(dining, 100)
    spend(dining, 180)

    visit root_path

    expect(figure("Dining Out")).to have_content("$180.00 of $150.00")
    expect(figure("Dining Out")[:class]).to include("text-status-danger")
    expect(row("Dining Out")).to have_css("[data-period-bar='100']")
    expect(row("Dining Out")).to have_css("[data-period-fill].bg-status-danger")
    expect(clause("Dining Out")).to have_content("overdrawn $80.00")
  end

  # The other direction of the over state, on a category that spent to the penny: exactly the plan
  # is the tidiest outcome there is, and reading it as trouble would be the same lie as `-$0.00`.
  it "leaves a category that spent exactly its plan in the quiet colour", :aggregate_failures do
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    fund(groceries, 400)
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
    fund(groceries, 400, on: Date.new(2026, 8, 15))
    spend(groceries, 310, on: Date.new(2026, 8, 20))
    spend(groceries, 50, on: Date.new(2026, 8, 10))

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(figure("Groceries")).to have_content("$310.00 of $400.00")
    expect(figure("Groceries")).to have_no_content("$360.00")
  end

  # SAVINGS GOALS KEEP THEIR TARGET BARS (spec §4), and the figure is what is SET ASIDE rather than
  # what was spent: "$424.00 of $2,400.00" is the row the categories band printed, and the word
  # "left" must stay off it for the reason the seventh state exists at all.
  it "keeps a savings goal's target bar", :aggregate_failures do
    goal = holder("Vacation", target_amount: 2_400)
    deposit(500)
    fund(goal, 424)

    visit root_path

    expect(figure("Vacation")).to have_content("set aside $424.00 of $2,400.00")
    expect(row("Vacation")).to have_no_content("left")
    expect(row("Vacation")).to have_no_content("spent")
    expect(row("Vacation")).to have_css("[data-period-bar='18']")
  end

  # ** THE TWO-LEVEL CLASSIFICATION, ON ONE ROW — carried with one correction stated. ** The
  # categories band's version of this example asserted `have_no_content("of $2,400.00")` on the whole
  # row, because the only thing the row printed was its STATUS and an anchor-dated goal's status is
  # its schedule rather than `saving`. This section prints a BAR as well, and the bar is drawn at the
  # CHROME level — `HoldingCalculator#saving_toward_a_target?`, holder + target, "a goal is a goal
  # whatever refills it" — which is the same predicate the impact card, the holdings card and the
  # categories index card all ask about this same category. So the target figure is on the row now,
  # deliberately, and the assertion moves to where the old one's point actually lived: the CLAUSE
  # reads the schedule and never `saving`.
  it "reads an anchor-dated goal by its schedule rather than as saving", :aggregate_failures do
    category = holder("House Deposit", target_amount: 2_400)
    create(:budget, category: category, amount: 300, interval_months: 1, anchor_date: Date.current + 2.months)
    deposit(1_000)
    fund(category, 600)

    visit root_path

    expect(clause("House Deposit")).to have_content("on track")
    expect(clause("House Deposit")).to have_no_content("of $2,400.00")
    expect(figure("House Deposit")).to have_content("set aside $600.00 of $2,400.00")
  end

  # ── THE CLAUSE (spec §4: the status vocabulary "where it earns its place") ─────────────────────

  # CARRIED FROM "shows a balance on an on-track category". The state word survives; the AMOUNT
  # beside it does not, because the bar has already printed the money and printing it twice in two
  # different denominations is the two-answers-on-one-row defect this design set out to remove.
  it "keeps the status vocabulary as a small clause without repeating the money", :aggregate_failures do
    deposit(2_000)
    rent = accumulating("Rent", amount: 2_000, due: Date.current + 2.months)
    fund(rent, 2_000)

    visit root_path

    expect(clause("Rent")).to have_content("on track")
    expect(clause("Rent")).to have_no_content("$2,000.00")
  end

  # NO CLAUSE ON A ROW THAT HAS NOTHING TO ADD. `left to spend` IS the bar, said backwards, so
  # printing it beside the bar would be the app answering one question twice.
  it "leaves the clause off a quiet envelope", :aggregate_failures do
    deposit(400)
    groceries = envelope("Groceries", rate: 400)
    fund(groceries, 400)
    spend(groceries, 100)

    visit root_path

    expect(figure("Groceries")).to have_content("$100.00 of $400.00")
    expect(row("Groceries")).to have_no_css("[data-period-clause]")
    expect(row("Groceries")).to have_no_content("left")
  end

  # CARRIED WHOLE from "marks a rate category whose period has ended, and only that one". Both
  # categories on ONE screen, at the identical holding and the identical rule, differing only in
  # which side of a period boundary their money arrived on — split into two examples the negative
  # half would pass against a view that never says "last period" at all.
  it "marks a rate category whose period has ended, and only that one", :aggregate_failures do
    deposit(1_000)
    overspend_on_both_sides_of_a_boundary

    visit root_path

    expect(clause("Swept")).to have_content("overdrawn $120.00 · last period")
    expect(clause("Live")).to have_content("overdrawn $120.00")
    expect(clause("Live")).to have_no_content("last period")
  end

  # Two rate categories at the identical holding and the identical rule, differing only in which side
  # of a period boundary their money arrived on. Twenty days back on a biweekly cadence anchored
  # today, so the swept one's rate period — measured from `last_funded_on` — closed before today.
  def overspend_on_both_sides_of_a_boundary
    swept = envelope("Swept", rate: 400, priority: 1)
    live = envelope("Live", rate: 400, priority: 2)
    fund(swept, 60, on: Date.current - 20.days)
    fund(live, 60, on: Date.current)
    spend(swept, 180)
    spend(live, 180)
  end

  # CARRIED FROM "a quiet category's due date". The date clause gates on the STATUS being quiet, not
  # on the row being quiet, and the two were briefly the same question — a category reading
  # `on track` lost the only date on its line.
  describe "a quiet category's due date", :aggregate_failures do
    def goal_with_rule(name, amount:, due:)
      holder(name, target_amount: 5_000).tap do |category|
        create(:budget, category: category, amount: amount, interval_months: 1, anchor_date: due)
      end
    end

    it "prints it when the category's own status is quiet" do
      due = Date.current + 2.months
      category = goal_with_rule("Old Goal", amount: 300, due: due)
      deposit(500)
      fund(category, 300)

      visit root_path

      expect(clause("Old Goal")).to have_content("on track")
      expect(clause("Old Goal")).to have_content(due.strftime("%b %-d"))
    end

    # The other direction, on a category whose OWN status needs attention: "overdrawn $50.00 ·
    # Oct 17" would date a debt with a deadline that belongs to something else.
    it "leaves it off when the category's own status needs attention" do
      due = Date.current + 2.months
      category = goal_with_rule("Late Goal", amount: 300, due: due)
      spend(category, 50)

      visit root_path

      expect(clause("Late Goal")).to have_content("overdrawn $50.00")
      expect(clause("Late Goal")).to have_no_content(due.strftime("%b %-d"))
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
    fund(envelope("Rent", rate: 400, priority: 1), 400)
    fund(envelope("Groceries", rate: 400, priority: 2), 400)
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
    fund(envelope("Groceries", rate: 400), 100)

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
      fund(groceries, 1_500)
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
