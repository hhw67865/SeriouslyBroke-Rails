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
# EVERY ASSERTION GOES THROUGH A HOOK: `[data-runway]`, `[data-tick="<rule id>"]`,
# `[data-tick-mark="<rule id>"]` (with `[data-tick-label]` beside each — fix round 1, LOW-4: two
# categories may each own an item called "Electric", and a hook keyed on the LABEL answers for both),
# `[data-today-mark]`, `[data-period-range]`,
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

  # TWO DATED BILLS ON ONE CATEGORY, TWO DAYS APART INSIDE THE PERIOD — the fixture behind every
  # example about two labels sharing one rail, and three lines none of them is about.
  def two_bills_one_period
    utilities = holder("Utilities")

    [
      bill_on_item(utilities, "Electric", amount: 120, due: Date.new(2026, 8, 24)),
      bill_on_item(utilities, "Water", amount: 30, due: Date.new(2026, 8, 26))
    ]
  end

  # TWO DATED BILLS ON THE SAME DAY — the fixture behind the dot nudge and behind the label
  # suppression, which are the two answers this panel gives to one collision.
  def two_bills_one_day
    utilities = holder("Utilities")

    [
      bill_on_item(utilities, "Electric", amount: 120, due: Date.new(2026, 8, 24)),
      bill_on_item(utilities, "Water", amount: 30, due: Date.new(2026, 8, 24))
    ]
  end

  # THE TWO HOOKS, FOUND BY THE RULE THAT OWNS THEM. Both take the `Budget` the fixture helpers
  # return, so no example in this file can be satisfied by another rule's mark.
  # THE SCREEN, READ AT THIS FILE'S FROZEN DAY — every example travels, and an example that reads it
  # twice (before and after a payment) says so twice.
  def read_home = travel_to(today) { visit root_path }

  def tick(rule) = find("[data-tick='#{rule.id}']")

  def tick_mark(rule) = find("[data-tick-mark='#{rule.id}']")

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.new(2026, 8, 14))
  end

  def set_aside(rule, amount, on: Date.new(2026, 8, 20))
    create(:adjustment, rule: rule, amount: amount, date: on)
  end

  # ** A PAID ONE-OFF IS OFF THE RAIL, AND OUT OF THE DUE TOTAL (two-shapes Task 3's carry (a)). **
  # A one-time bill's occurrence NEVER rolls — there is no interval to roll onto — so its date stays
  # inside this period for ever after the money has gone out, and the tick it drew was RED: paying
  # the bill empties the fund, and `ClaimLine#fund_short?` read the emptiness as a shortfall. The
  # pace line then said `$120.00 due before Aug 27` about a bill already paid, and named it short.
  #
  # BOTH DIRECTIONS ON ONE FIXTURE, because a page that drew no ticks at all would pass the second
  # half alone: the same rule has a mark and a due total before the payment and neither after.
  # THE ONE FIXTURE BOTH HALVES READ: $120 due Aug 24 on the Utilities category's Water lane.
  def unpaid_water_bill
    deposit(1_000)
    water = create(:item, category: holder("Utilities"), name: "Water")
    [water, bill(water.category, amount: 120, due: Date.new(2026, 8, 24), item: water)]
  end

  it "takes a paid one-off off the rail and out of the total", :aggregate_failures do
    water, rule = unpaid_water_bill
    read_home

    expect(page).to have_css("[data-tick-mark='#{rule.id}']")
      .and have_css("[data-due-total]", text: "$120.00 due")

    create(:entry, item: water, amount: 120, date: Date.new(2026, 8, 18))
    read_home

    expect(page).to have_no_css("[data-tick-mark='#{rule.id}']")
      .and have_css("[data-due-total]", text: "Nothing is due before Aug 27")
      .and have_no_css("[data-short-list]")
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
    rule = bill(holder("Utilities"), amount: 120, due: Date.new(2026, 8, 24))

    travel_to(today) { visit root_path }

    # THE POSITION IS THE GROUP'S NOW, NOT THE DOT'S: a tick is one element — amount, dot, name —
    # placed once, so the words cannot be at a different percent from the mark they belong to.
    expect(tick(rule)[:style]).to include("79%")
    expect(tick_mark(rule)["data-tick-label"]).to eq("Utilities")
    expect(tick(rule)).to have_content("$120.00").and have_content("ready")
    expect(page).to have_css("[data-due-total]", text: "$120.00 due before Aug 27")
    expect(page).to have_no_css("[data-short-list]")
  end

  # ** THE WORDS ARE ON THE RAIL, NOT IN A LIST UNDER IT (2026-09-06 layout ruling). ** They were
  # stacked below the bar — the same ticks printed twice, once as marks and once as rows — so a
  # reader had to match a dot to a row by eye and the panel said everything two ways. The panel is
  # full width now and a fortnight is most of the page, so each label stands where its money is:
  # AMOUNT ABOVE THE DOT, NAME AND STATE BELOW IT.
  #
  # GEOMETRY RATHER THAN CLASS NAMES, because "above" is the whole assertion and a class that
  # stopped positioning would still render both spans in the right order in the DOM. The dot's
  # centre is checked against both, and the two labels are checked against each other, so a group
  # that collapsed onto one line — which is what a lost `flex-col` produces — fails.
  it "stands each tick's words on the rail, amount above the dot and name below", :aggregate_failures do
    deposit(1_000)
    rule = bill_on_item(holder("Utilities"), "Electric", amount: 120, due: Date.new(2026, 8, 24))

    travel_to(today) { visit root_path }

    dot = tick_mark(rule).native.rect
    amount = tick(rule).find("[data-tick-amount]").native.rect
    name = tick(rule).find("[data-tick-name]").native.rect
    # THE DOT IS STILL ON THE RAIL, which is what the symmetric column above and below it buys: a
    # group that centred itself instead of its dot would drift off the bar as soon as the two labels
    # stopped being the same height.
    rail = find("[data-period-progress]").native.rect

    expect(amount.y + amount.height).to be <= dot.y
    expect(name.y).to be >= dot.y + dot.height
    expect(dot.y + (dot.height / 2)).to be_within(2).of(rail.y + (rail.height / 2))
  end

  # ** THE MONEY IS NOT THERE, AND THE PANEL SAYS SO THREE WAYS: ** a red mark, the row's own words,
  # and the pace line naming it. PLANTED — the $120 catch-up is knocked to **$80** by a −$40
  # adjustment dated inside the period, so the gap is **$40.00**.
  it "names a rule whose money is not there for the day", :aggregate_failures do
    deposit(1_000)
    rule = bill_on_item(holder("Utilities"), "Electric", amount: 120, due: Date.new(2026, 8, 24))
    set_aside(rule, -40)

    travel_to(today) { visit root_path }

    expect(tick_mark(rule)[:class]).to include("bg-status-danger")
    expect(tick(rule)).to have_content("$40.00 short")
    expect(page).to have_css("[data-short-list]", text: "Electric is $40.00 short")
  end

  # ** THE WINDOW, BOTH DIRECTIONS, ON THE SCREEN. ** A date in the NEXT period is not on this ruler
  # (Aug 30 is past Aug 27), and neither is a rate rule, which has no day at all. The panel still
  # draws — the ruler and the pace line are the answer.
  #
  # ** AND IT SAYS SO IN WORDS (fix wave — Task 5's minor). ** A quiet period is the ORDINARY period,
  # and the due-total line was simply absent on it — leaving the panel a rail, one pace sentence and
  # two-thirds of a card of white space at 1440, with no statement anywhere that nothing is coming.
  # The line is there in both arms now: a figure when something is due, and this sentence when
  # nothing is. It is not "$0.00 due", which reports nothing; it is the answer.
  it "leaves off a date past the period's close and a rule with no date at all", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", 400)
    bill(holder("Insurance", priority: 2), amount: 200, due: Date.new(2026, 8, 30))

    travel_to(today) { visit root_path }

    expect(page).to have_css("[data-runway]")
    expect(page).to have_no_css("[data-tick-mark]")
    expect(page).to have_css("[data-due-total]", text: "Nothing is due before Aug 27")
    expect(page).to have_no_content("$0.00 due")
    expect(page).to have_css("[data-pace-line]")
  end

  # ── ** TWO MARKS ON ONE DAY (fix round 1 — LOW-3/LOW-4) ** ────────────────────────────────────

  # ** A BILL DUE TODAY PUTS A 12px TICK EXACTLY WHERE THE 2px TODAY MARK IS. ** Aug 20 is day 7 of
  # 14, so both sit at `round(7 ÷ 14 × 100)` = 50% — the one afternoon the mark matters most, and the
  # afternoon it was invisible before this round. The mark is drawn LAST (a later sibling paints over
  # an earlier one) with `z-10` and a white ring, and the geometry says the two really do overlap:
  # the mark's centre falls inside the tick's rect, which is the state a "fix" that simply moved the
  # mark aside would fail.
  it "keeps today's mark visible under a tick due today", :aggregate_failures do
    deposit(1_000)
    rule = bill(holder("Utilities"), amount: 120, due: today)

    travel_to(today) { visit root_path }

    mark = find("[data-today-mark]").native.rect
    dot = tick_mark(rule).native.rect

    expect(mark.x + (mark.width / 2)).to be_between(dot.x, dot.x + dot.width)
    # DRAWN AFTER THE TICK, AND ABOVE IT: the sibling combinator is document order, which is what
    # decides the paint order inside one stacking context, and `z-10` is what decides it anyway.
    expect(page).to have_css("[data-tick] ~ [data-today-mark].z-10")
  end

  # ** TWO BILLS DUE ON ONE DAY ARE TWO DOTS. ** Both fall on Aug 24, so both are placed at the same
  # percent; the second is nudged 6px — half its own width — so neither is hidden by the other.
  # PINNED ON x, because a `left:` that ignored the nudge would put them at the same place and still
  # render two elements.
  it "nudges a second tick that falls on the same day", :aggregate_failures do
    deposit(1_000)
    electric, water = two_bills_one_day

    travel_to(today) { visit root_path }

    # WITHIN A TENTH OF A PIXEL rather than exactly 6: the dot is centred inside its tick's group
    # now, and a group whose label is an odd number of pixels wide centres on a half pixel. The
    # assertion is the nudge, and a `left:` that ignored it would put both dots at the same x.
    expect(tick_mark(water).native.rect.x - tick_mark(electric).native.rect.x).to be_within(0.1).of(6)
  end

  # ── ** A LABEL NEVER OVERPRINTS ANOTHER (fix round 2 — MED-1/2) ** ────────────────────────────
  #
  # ** 6px SEPARATES TWO DOTS AND DOES NOTHING FOR TWO NAMES. ** The fixture directly above draws
  # "Electric · ready" and "Water · ready" — about 96px each, `whitespace-nowrap` — centred 6px
  # apart, which is two sentences printed through each other. The clearance suppresses the second
  # one's words: its DOT is untouched (the example above still passes, on the same fixture), its
  # amount and name go `invisible`, and the pace block's list appears to say what the rail stopped
  # saying.
  #
  # BOTH DIRECTIONS ON THE HOOK: `have_no_css` is visible-only, so it is the assertion that the words
  # are not readable; `visible: :all` is the assertion that they are still IN the group, which is
  # what keeps it symmetric about its dot. A fix that deleted the span would pass the first and fail
  # the second, and would drop the dot off the rail.
  it "suppresses the second label when two ticks fall on one day", :aggregate_failures do
    deposit(1_000)
    electric, water = two_bills_one_day

    travel_to(today) { visit root_path }

    expect(tick(electric)).to have_css("[data-tick-name]", text: "Electric · ready")
    expect(tick(water)).to have_no_css("[data-tick-name]").and have_css("[data-tick-name]", visible: :all)
    expect(find("[data-tick-list]")).to have_content("$120.00 Electric · ready").and have_content("$30.00 Water · ready")
  end

  # ** TWO TICKS A WEEK APART BOTH KEEP THEIR WORDS, AND THERE IS NO LIST. ** Aug 17 is day 4 (29%)
  # and Aug 24 is day 11 (79%) — fifty points of rail between them, well past the clearance — so the
  # rail says everything and the list under it would be the same words twice. This is the other
  # direction of the gate, and without it "suppress" could be spelled "always suppress".
  it "labels two ticks a week apart and prints no list under them", :aggregate_failures do
    deposit(1_000)
    utilities = holder("Utilities")
    rent = bill_on_item(utilities, "Rent", amount: 60, due: Date.new(2026, 8, 17))
    electric = bill_on_item(utilities, "Electric", amount: 120, due: Date.new(2026, 8, 24))

    travel_to(today) { visit root_path }

    expect(tick(rent)).to have_css("[data-tick-name]", text: "Rent · ready")
    expect(tick(electric)).to have_css("[data-tick-name]", text: "Electric · ready")
    expect(page).to have_no_css("[data-tick-list]")
  end

  # ** THE COLLISION THAT FULL WIDTH DOES NOT FIX EITHER. ** Two ticks on ADJACENT days are one
  # fourteenth of the rail apart — about 75px at 1440 and less at 1024, against a ~96px name — so
  # "it fits on a big screen" was never true. Measured at 1024, the narrowest desktop the sidebar
  # leaves room at: the second tick's words are suppressed and the list carries them.
  describe "at 1024" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 1024, height: 768, deviceScaleFactor: 1, mobile: false
      )
    end

    it "suppresses the second label when two ticks fall on adjacent days", :aggregate_failures do
      deposit(1_000)
      utilities = holder("Utilities")
      electric = bill_on_item(utilities, "Electric", amount: 120, due: Date.new(2026, 8, 24))
      water = bill_on_item(utilities, "Water", amount: 30, due: Date.new(2026, 8, 25))

      travel_to(today) { visit root_path }

      expect(tick(electric)).to have_css("[data-tick-name]", text: "Electric · ready")
      expect(tick(water)).to have_no_css("[data-tick-name]")
      expect(find("[data-tick-list]")).to have_content("$30.00 Water · ready")
    end
  end

  # ** TWO ITEMS WITH ONE NAME, IN TWO CATEGORIES (LOW-4). ** "Electric" is an ordinary item name and
  # nothing stops two categories owning one each. Keyed on the label, one hook answered for both —
  # ambiguous to a spec and indistinguishable to a reader. Keyed on the RULE, each mark is its own,
  # and the label rides beside it as what it SAYS rather than as what it IS.
  it "tells two same-named items apart by their rules", :aggregate_failures do
    deposit(2_000)
    first = bill_on_item(holder("Utilities"), "Electric", amount: 120, due: Date.new(2026, 8, 24))
    second = bill_on_item(holder("Workshop", priority: 2), "Electric", amount: 40, due: Date.new(2026, 8, 26))

    travel_to(today) { visit root_path }

    # TWO MARKS AND TWO GROUPS carry the label — it is on both halves of a tick — so the count is
    # asserted on the MARKS, which is the half a shared hook made ambiguous.
    #
    # ** `visible: :all` ON THE SECOND (fix round 2 — MED-1/2). ** Aug 24 and Aug 26 are 14 points of
    # rail apart, inside the label clearance, so the second tick's words are suppressed here — which
    # is this fixture meeting the new rule rather than a hole in it. What this example is about is
    # IDENTITY: each group holds its own amount, keyed on its own rule, whether or not the screen is
    # currently reading it out. The suppression itself is pinned by its own examples above.
    expect(page).to have_css("[data-tick-mark][data-tick-label='Electric']", count: 2)
    expect(tick(first)).to have_css("[data-tick-amount]", text: "$120.00")
    expect(tick(second)).to have_css("[data-tick-amount]", text: "$40.00", visible: :all)
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

    # ** THE AMOUNT KEEPS ITS PLACE AND THE NAME MOVES INTO THE PACE BLOCK (2026-09-06 layout
    # ruling). ** Two labels two days apart put their names through each other at 375px — that is
    # the collision the old stacked list was avoiding — but the AMOUNT is short, it is the figure,
    # and it is the half worth reading in place. So the amount stays above its dot and the name
    # comes down into the pace block, where a line may wrap.
    #
    # THE NAME IS `invisible` RATHER THAN `hidden`, which is the one implementation fact this
    # example has to know: the tick's column is symmetric about its dot, so taking the name's half
    # away would drop the dot off the rail. Capybara treats `visibility: hidden` as not visible,
    # which is exactly the assertion below, and `visible: :all` is how the geometry still reads it.
    it "keeps the amount on the rail and moves the name into the pace line", :aggregate_failures do
      deposit(1_000)
      electric, water = two_bills_one_period

      travel_to(today) { visit root_path }

      # THE AMOUNT, ABOVE ITS DOT, AND STILL ON THE RAIL.
      dot = tick_mark(electric).native.rect
      amount = tick(electric).find("[data-tick-amount]").native.rect
      expect(amount.y + amount.height).to be <= dot.y

      # THE NAME IS NOT READABLE ON THE RAIL, and it is not missing from the screen: both ticks say
      # themselves in the pace block, in words, inside the viewport.
      expect(tick(electric)).to have_no_css("[data-tick-name]")
      expect(find("[data-pace]")).to have_content("$120.00 Electric · ready").and have_content("$30.00 Water · ready")

      words = find("[data-tick-words='#{water.id}']").native.rect
      expect(words.x + words.width).to be <= 375
    end
  end
end
