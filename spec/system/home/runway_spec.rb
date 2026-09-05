# frozen_string_literal: true

require "rails_helper"

# THE RUNWAY — this period as a line, with a mark on every day money is needed (two-shapes spec §3).
# A new panel, and the successor of the hero card's period bar: three examples come here from
# `hero_spec.rb` (now `money_spec.rb`) with their hooks intact, because the period is this panel's
# subject now and drawing it in two places was how one screen came to print "7 days left" twice.
#
# ── CARRIED FROM hero_spec.rb:
#
#   * "draws the period as a bar with the days that are left" → "draws the period with today's mark
#     and the days that are left", same grid, same 50%, same "7 days left".
#   * "says one day rather than 1 days on the closing eve" → unchanged.
#   * "shows no period bar before a period is declared" → "draws nothing before a period is
#     declared", asserted against `[data-runway]` — the whole panel is absent, not just its bar.
#
# EVERY ASSERTION GOES THROUGH A HOOK: `[data-runway]`, `[data-tick="<name>"]`,
# `[data-tick-mark="<name>"]`, `[data-today-mark]`, `[data-period-range]`,
# `[data-period-progress]`, `[data-period-days-left]`, `[data-pace]` and its three lines
# (`[data-pace-line]`, `[data-due-total]`, `[data-short-list]`).
#
# `travel_to` WRAPS ONLY THE VISIT — HomeController reads the clock at request time — and every date
# is a planted literal, never a lazy `Date.current` resolved inside the travelled block (CLAUDE.md's
# third flake cause).
RSpec.describe "Home Runway", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14), typical_income: 2_400)
  end
  # THE GRID THIS WHOLE FILE SHARES: biweekly anchored Aug 14 2026, so the period containing Aug 20
  # is **Aug 14–27** — fourteen days, with Aug 20 as day 7.
  let(:today) { Date.new(2026, 8, 20) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `checking` FIRST, so it is the account the `:account` trait makes default, and `sign_in` touches
  # the user at REAL NOW — which is what keeps every date below a literal.
  before do
    checking
    sign_in user, scope: :user
  end

  def holder(name, priority: 1, funded_since: Date.new(2026, 8, 14))
    create(:category, :expense, user: user, name: name, priority: priority, funded_since: funded_since)
  end

  # A CATEGORY WITH A RATE RULE — no day, so no tick: the runway is about days money is NEEDED on.
  def envelope(name, amount, priority: 1)
    holder(name, priority: priority).tap { |category| create(:budget, :per_period_rate, category: category, amount: amount) }
  end

  # A ONE-TIME BILL DUE ON A NAMED DAY. `created_at:` is planted for the ruling of 2026-09-03: a rule
  # accrues from the LATER of its category's funding date and its own birthday, so a rule the factory
  # writes at real-now walks nothing at all inside a `travel_to` that has gone backwards.
  def bill(category, amount:, due:, item: nil)
    create(
      :budget,
      :one_time,
      category: category,
      amount: amount,
      anchor_date: due,
      item: item,
      created_at: Time.zone.local(2026, 8, 14)
    )
  end

  # A BILL ON AN ITEM OF ITS CATEGORY — the lane a tick is labelled by. Two lines of fixture that
  # every "named rule" example below needs and none of them is about.
  def bill_on_item(category, name, amount:, due:)
    bill(category, amount: amount, due: due, item: create(:item, category: category, name: name))
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.new(2026, 8, 14))
  end

  def set_aside(rule, amount, on: Date.new(2026, 8, 20))
    create(:adjustment, rule: rule, amount: amount, date: on)
  end

  # ── THE RULER (carried from the hero's bar) ────────────────────────────────────────────────────

  # Aug 14 – Aug 27 is fourteen days; Aug 20 is day 7 of it, so `round(7 ÷ 14 × 100)` = 50% and seven
  # days remain.
  it "draws the period with today's mark and the days that are left", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-period-range]", text: "Aug 14")
    expect(page).to have_css("[data-period-range]", text: "Aug 27")
    expect(page).to have_css("[data-period-days-left]", text: "7 days left")
    expect(page).to have_css("[data-period-progress='50']")
    expect(page).to have_css("[data-today-mark]")
  end

  # The singular, because "1 days left" is the kind of thing a reader stops trusting a screen over.
  it "says one day rather than 1 days on the closing eve" do
    deposit(1_000)

    travel_to(Date.new(2026, 8, 26)) { visit root_path }

    expect(page).to have_css("[data-period-days-left]", text: "1 day left")
  end

  # NO PERIOD, NO PICTURE. `User#period_containing` falls back to the calendar month, which is right
  # for a normaliser and a lie on a panel that would draw a fortnight nobody declared — so the whole
  # panel is absent rather than drawn empty.
  it "draws nothing before a period is declared", :aggregate_failures do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-runway]")
    # THE REST OF THE SCREEN IS UNCONDITIONAL, and this is where that matters most: a user who has
    # declared nothing still gets both money figures.
    expect(page).to have_css("[data-free]")
  end

  # ── THE TICKS ─────────────────────────────────────────────────────────────────────────────────

  # ** A BILL DUE INSIDE THE PERIOD, WITH ITS MONEY THERE. ** Aug 24 is `24 − 14 + 1` = day 11 of 14,
  # so the mark sits at `round(11 ÷ 14 × 100)` = **79%**. The category is funded on the boundary and
  # the rule is born there, so §3.2's walk visits ONE period, `periods_left` is 1 against a date
  # inside it, and the catch-up share is the whole $120 — the tick is ready and the pace line totals
  # it.
  it "marks a day money is needed on and says it is ready", :aggregate_failures do
    deposit(1_000)
    bill(holder("Utilities"), amount: 120, due: Date.new(2026, 8, 24))

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-tick-mark='Utilities'][style*='79%']")
    expect(page).to have_css("[data-tick='Utilities']", text: "$120.00")
    expect(page).to have_css("[data-tick='Utilities']", text: "ready")
    expect(page).to have_css("[data-due-total]", text: "$120.00 due before Aug 27")
    expect(page).to have_no_css("[data-short-list]")
  end

  # ** THE MONEY IS NOT THERE, AND THE PANEL SAYS SO THREE WAYS: ** a red mark, the row's own words,
  # and the pace line naming it. PLANTED — the $120 catch-up is knocked to **$80** by a −$40
  # adjustment dated inside the period, so the gap is **$40.00**.
  it "names a rule whose money is not there for the day", :aggregate_failures do
    deposit(1_000)
    set_aside(bill_on_item(holder("Utilities"), "Electric", amount: 120, due: Date.new(2026, 8, 24)), -40)

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-tick-mark='Electric'].bg-status-danger")
    expect(page).to have_css("[data-tick='Electric']", text: "$40.00 short")
    expect(page).to have_css("[data-short-list]", text: "Electric is $40.00 short")
  end

  # ** THE WINDOW, BOTH DIRECTIONS, ON THE SCREEN. ** A date in the NEXT period is not on this ruler
  # (Aug 30 is past Aug 27), and neither is a rate rule, which has no day at all. The panel still
  # draws — the ruler and the pace line are the answer — and says nothing about what is due.
  it "leaves off a date past the period's close and a rule with no date at all", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", 400)
    bill(holder("Insurance", priority: 2), amount: 200, due: Date.new(2026, 8, 30))

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-runway]")
    expect(page).to have_no_css("[data-tick-mark]")
    expect(page).to have_no_css("[data-due-total]")
    expect(page).to have_css("[data-pace-line]")
  end

  # ── THE PACE LINE, BOTH SIGNS OF FREE ─────────────────────────────────────────────────────────

  # FREE ABOVE ZERO: $1,000 in with a $400 rate rule leaves **$600**, and seven days remain, so
  # `600 ÷ 7` = **$85.71** a day.
  it "says what a day may cost while free is above zero", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", 400)

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-pace-line]", text: "$85.71 a day is fine for the rest of the period")
    expect(page).to have_no_css("[data-pace-line].text-status-danger")
  end

  # FREE BELOW ZERO: $150 in against the same $400 rule is −$250 over seven days — `250 ÷ 7` =
  # **$35.71** — and it is the SHORTFALL STRIP'S OWN SENTENCE, which is the point of the shared
  # `HomeHelper#pace_words`: both panels are on this screen at once and they say one thing.
  it "says what a day must come down by while free is under", :aggregate_failures do
    deposit(150)
    envelope("Groceries", 400)

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-pace-line]", text: "Spending $35.71 a day less for the rest of this period lands it at zero")
    expect(page).to have_css("[data-shortfall-pace]", text: "Spending $35.71 a day less")
  end

  # ── THE NARROW BREAKPOINT ─────────────────────────────────────────────────────────────────────

  describe "on a narrow screen" do
    # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE (see `money_spec.rb`'s own
    # note for the five measurements behind this). Chrome refuses to make a headless window narrower
    # than 500px, so every window-based spelling of a 375 test is a 500 test wearing a 375 label.
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # ** THE TICKS KEEP THEIR WORDS AT 375 (§3), AND THE RULING IS THAT THE WORDS STACK RATHER THAN
    # ROTATE. ** The mock labels each mark in place; two bills three days apart put their labels
    # through each other at this width, and a label that has to be READ is worth more than one that
    # has to be positioned. So the marks stay on the rail (with the full label in a `title`) and the
    # words go under it, one tick per line — which is what the geometry below measures: the second
    # tick's row sits BELOW the first rather than beside it, and neither leaves the viewport.
    it "keeps every tick's words inside a 375px viewport, one to a line", :aggregate_failures do
      deposit(1_000)
      utilities = holder("Utilities")
      bill_on_item(utilities, "Electric", amount: 120, due: Date.new(2026, 8, 24))
      bill_on_item(utilities, "Water", amount: 30, due: Date.new(2026, 8, 26))

      travel_to(today) { visit root_path }

      expect(page).to have_css("[data-tick='Electric']", text: "$120.00")

      first = page.find("[data-tick='Electric']").native.rect
      second = page.find("[data-tick='Water']").native.rect

      # THE SECOND TICK IS BELOW THE FIRST (they stack) and its right edge is inside the viewport —
      # the two facts a row of labels along a rail fails at this width.
      expect(second.y).to be > first.y
      expect(second.x + second.width).to be <= 375
    end
  end
end
