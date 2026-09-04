# frozen_string_literal: true

require "rails_helper"

# SET ASIDE, TAKE BACK, TOP UP, REDUCE AND SKIP (computed-claims spec §3.3), and the §3.5 offer a
# cadence change makes — the whole of what a user can DO to a claim without editing the rule.
#
# The subject of every example is the FIGURE MOVING BY EXACTLY THE AMOUNT THE ROW SAYS. A screen
# that wrote the row and printed a claim computed some other way would pass a test that only checked
# the row existed, and the two figures disagreeing is the one failure this feature can have.
#
# `Capybara.exact` is unset in this suite, so every assertion is scoped with `within` or through a
# data hook — an unscoped `have_content("Groceries")` matches the group heading, the rule row and
# the nav at once.
RSpec.describe "Budget page adjustments", type: :system do
  # MONTHLY, ANCHORED ON THE FIRST, so a period is a calendar month and every planted literal below
  # is arithmetic anyone can redo by hand. The anchor is a fixed date rather than one derived from
  # `Date.current`: `period_boundaries` extends the series backward from the anchor as well as
  # forward, so any first-of-the-month answers the same boundaries whatever today is.
  let(:user) do
    create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1), typical_income: 4_000)
  end

  before { sign_in user, scope: :user }

  def holder(name, priority: 1, target: nil)
    create(:category, :expense, :funded, user: user, name: name, priority: priority, target_amount: target)
  end

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  def rule_row(name) = find("[data-rule='#{name}']")

  # OPEN THE PANEL FIRST. `<details>` keeps its contents out of the accessibility tree while it is
  # closed, so Capybara cannot see a field inside one — which is the affordance working.
  def open_adjust(name)
    find("[data-adjust='#{name}'] summary").click
    find("[data-adjust='#{name}'] [data-adjust-planned]")
  end

  # OPEN, TYPE, PRESS — the one gesture every example but the skip makes. The BUTTON is the
  # parameter, because the direction is what it carries: the field types a magnitude and never a
  # minus.
  def change_by(name, amount, button)
    open_adjust(name)
    within("[data-adjust='#{name}']") do
      fill_in "How much", with: amount.to_s
      click_button button
    end
  end

  # ── §3.3, THE ACCRUING SHAPE: set aside, take back, skip ──────────────────────────────────────

  # A $1,200 goal fed by a $150-a-period rule written today: the walk visits ONE period (accrual
  # starts at the later of the category's funding date and the rule's own birth), so this period
  # plans `min($150, $1,200 − $0)` = $150 and the fund holds $150.
  describe "a fund that accrues toward a target" do
    before do
      rate(holder("Vacation", target: 1_200), 150)
      visit budget_page_path
    end

    it "says what it has built up and what is going in this period", :aggregate_failures do
      within(rule_row("Vacation")) do
        expect(page).to have_css("[data-rule-figure]", text: "$150.00 built up of $1,200.00")
      end
      open_adjust("Vacation")
      expect(find("[data-adjust='Vacation'] [data-adjust-planned]")).to have_content("$150.00 going in this period")
    end

    # ** SKIP IS −PLANNED, AND THE FUND MOVES BY EXACTLY THAT. ** Both halves are asserted and
    # neither is enough alone: the row alone would pass on a delta the claim ignored, and the figure
    # alone would pass on a page that had simply stopped accruing. $150.00 built up, one click,
    # $0.00 built up and one −$150.00 row dated today.
    it "skips this period by writing minus the planned share, dated today", :aggregate_failures do
      open_adjust("Vacation")
      find("[data-adjust='Vacation'] [data-adjust-skip]").click

      expect(page).to have_content("Skipped this period for Vacation")
      within(rule_row("Vacation")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 built up of $1,200.00")
        expect(page).to have_css("[data-change-amount]", text: "-$150.00")
        expect(page).to have_content(Date.current.strftime("%b %-d"))
      end
      expect(user.all_budgets.first.adjustments.sole.amount).to eq(-150)
    end

    # ** SKIP MEANS "ACCRUE NOTHING THIS PERIOD", SO ONCE IT HAS THE BUTTON IS GONE (fix round
    # MED-2). ** A second press could only be a raid on the fund's prior savings wearing the skip's
    # words, and the panel is where that has to be refused: the flash still says "skipped" whatever
    # the row does. The panel is REOPENED after the redirect — `<details>` closes on navigation —
    # and the amount field beside it is asserted still there, so an example that simply failed to
    # find an open panel would not pass this.
    it "offers no skip once the period accrues nothing", :aggregate_failures do
      open_adjust("Vacation")
      find("[data-adjust='Vacation'] [data-adjust-skip]").click
      expect(page).to have_content("Skipped this period for Vacation")

      open_adjust("Vacation")

      expect(page).to have_css("[data-adjust='Vacation'] input[name='amount']")
      expect(page).to have_no_css("[data-adjust='Vacation'] [data-adjust-skip]")
    end

    # ** THE SKIP TAKES BACK THE WHOLE ACCRUAL AND NOT THE PLAN (fix round MED-2). ** $150 planned
    # plus $250 set aside is $400 going in this period; a skip of −$150 would leave $250 still
    # accruing under a flash saying the period was skipped. The row's own figure is the assertion:
    # $400.00 built up before, $0.00 after, and one −$400.00 delta to explain it.
    it "skips a period that has already been topped up by taking back the whole accrual", :aggregate_failures do
      change_by("Vacation", 250, "Set aside")
      expect(page).to have_css("[data-rule-figure]", text: "$400.00 built up of $1,200.00")

      open_adjust("Vacation")
      find("[data-adjust='Vacation'] [data-adjust-skip]").click

      within(rule_row("Vacation")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 built up of $1,200.00")
        expect(page).to have_css("[data-change-amount]", text: "-$400.00")
      end
    end

    # THE POSITIVE HALF, in the words this shape uses. $150 built up plus $250 set aside is $400,
    # which is under the $1,200 target — so the figure is the sum and not the cap.
    it "sets money aside and the fund holds it", :aggregate_failures do
      change_by("Vacation", 250, "Set aside")

      expect(page).to have_content("Set aside $250.00 for Vacation")
      within(rule_row("Vacation")) do
        expect(page).to have_css("[data-rule-figure]", text: "$400.00 built up of $1,200.00")
      end
    end

    # THE NEGATIVE HALF, and it is NOT the same click as a skip: $50 taken back leaves $100, where a
    # skip would leave $0. The pair is what says the sign comes off the button rather than off the
    # shape of the rule.
    it "takes money back out of the fund", :aggregate_failures do
      change_by("Vacation", 50, "Take back")

      expect(page).to have_content("Took back $50.00 from Vacation")
      within(rule_row("Vacation")) do
        expect(page).to have_css("[data-rule-figure]", text: "$100.00 built up of $1,200.00")
      end
    end
  end

  # ── §3.1, THE RATE SHAPE: top up and reduce ───────────────────────────────────────────────────

  describe "a rate rule's envelope" do
    before do
      rate(holder("Groceries"), 400)
      visit budget_page_path
    end

    # A RATE RULE SAYS SPENT-OF-RATE, NEVER BUILT UP (§3.4) — use-it-or-lose-it means nothing is ever
    # built up, and printing "$0.00 built up" over an envelope carrying $400 is the confusion
    # `ClaimCalculator#built_up` refuses. The negative half is asserted, so a row that printed both
    # would fail. (Task 3 replaced Task 2's `$400.00 claimed` with the §3.4 row it named as the
    # successor; the CLAIM is the difference between the two figures, and nothing spent makes it the
    # whole $400.)
    it "says what it claims this period and offers no skip", :aggregate_failures do
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $400.00")
        expect(page).to have_no_content("built up")
      end
      open_adjust("Groceries")
      expect(page).to have_no_css("[data-adjust='Groceries'] [data-adjust-skip]")
    end

    it "raises this period's claim by exactly the top-up", :aggregate_failures do
      change_by("Groceries", 50, "Top up this period")

      expect(page).to have_content("Topped up Groceries by $50.00 this period")
      within(rule_row("Groceries")) { expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $450.00") }
    end

    it "lowers it by exactly the reduction", :aggregate_failures do
      change_by("Groceries", 50, "Reduce this period")

      expect(page).to have_content("Reduced Groceries by $50.00 this period")
      within(rule_row("Groceries")) { expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $350.00") }
    end

    # ** REMOVING ONE PUTS THE FIGURE BACK EXACTLY. ** A delta is a row and nothing else — there is
    # no second place the $50 was written — so deleting it must leave the claim where it started.
    # The list is asserted GONE as well as the figure restored: a row still on screen over a figure
    # that had moved back would be the two disagreeing.
    it "restores the claim when the row is removed", :aggregate_failures do
      change_by("Groceries", 50, "Top up this period")
      expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $450.00")

      within(rule_row("Groceries")) { click_button "Remove" }

      expect(page).to have_content("Removed the $50.00 top-up on Groceries")
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $400.00")
        expect(page).to have_no_css("[data-rule-changes]")
      end
    end
  end

  # ── §3.3, WHERE A DELTA MAY BE DATED ──────────────────────────────────────────────────────────

  # ** THE PANEL SAYS WHERE THE RULE COUNTS, AND THE FIELD MEETS THE BOUND BEFORE THE 422 DOES
  # (fix round 2, NEW-5). ** `AdjustmentForm` refuses a date outside `ClaimCalculator#countable_span`
  # and that stays the law — but a user who learns the bound only from a refusal is typing into a
  # field that never said what it would take, and the panel's hint used to state the opposite of the
  # law outright ("It only changes this period", on a fund whose span reaches back to the day it was
  # written). Both readings come off the row's own span, so the words and the attributes cannot
  # disagree with the writer or with each other.
  #
  # THE TWO SHAPES HAVE DIFFERENT SPANS BY CONSTRUCTION: the fund was written last month, so its
  # walk opens at the first of that month; the envelope carries nothing from last period and opens
  # at the first of this one. A hint or a `min` derived from the current period alone would answer
  # the same for both and fail one half.
  describe "where a delta may be dated" do
    before do
      create(
        :budget,
        :per_period_rate,
        category: holder("Vacation", priority: 1, target: 1_200),
        amount: 150,
        created_at: 1.month.ago
      )
      rate(holder("Groceries", priority: 2), 400)
      visit budget_page_path
    end

    def date_field(name) = find("[data-adjust='#{name}'] input[name='date']")

    it "words the hint per shape and bounds the date field by the same span", :aggregate_failures do
      opened_on = 1.month.ago.to_date.beginning_of_month

      open_adjust("Vacation")
      expect(find("[data-adjust='Vacation'] [data-adjust-hint]"))
        .to have_content("Counts from #{opened_on.strftime("%b %-d")} to today")
      expect(date_field("Vacation")[:min]).to eq(opened_on.to_s)
      expect(date_field("Vacation")[:max]).to eq(Date.current.to_s)

      open_adjust("Groceries")
      expect(find("[data-adjust='Groceries'] [data-adjust-hint]")).to have_content("This period only, up to today")
      expect(date_field("Groceries")[:min]).to eq(Date.current.beginning_of_month.to_s)
      expect(date_field("Groceries")[:max]).to eq(Date.current.to_s)
    end
  end

  # ── §3.5, THE CADENCE OFFER ───────────────────────────────────────────────────────────────────

  # $400 a period on a monthly grid is $4,800 a year; on a fortnightly one the same digits are
  # $10,400. The ratio is 12/26, so the offer reads $400.00 → $184.62 (400 × 12 ÷ 26 = 184.615…,
  # rounded to the cent).
  describe "changing how long a period is" do
    before do
      rate(holder("Groceries"), 400)
      visit budget_page_path
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"
    end

    it "asks before saving, and has saved nothing yet", :aggregate_failures do
      expect(page).to have_css("[data-cadence-confirm]")
      within("[data-cadence-line='Groceries']") do
        expect(page).to have_css("[data-cadence-now]", text: "$400.00")
        expect(page).to have_css("[data-cadence-scaled]", text: "$184.62")
      end
      expect(page).to have_content("Nothing has been saved yet")
      expect(user.reload.period_cadence).to eq("monthly")
    end

    # ** ONE `id` PER ELEMENT ON THIS PAGE (fix wave — LOW-6). ** The confirm panel carries the
    # pending declaration as hidden fields and the declaration form below it still renders the SELECT
    # the user typed into, so `hidden_field_tag "user[period_cadence]"` and that select both derived
    # `id="user_period_cadence"` — two elements, one id, which is invalid HTML and makes any lookup
    # by id (a label's `for`, `find_field`, a script) a coin toss. The pending value is named for
    # what it is now.
    #
    # THE WHOLE DOCUMENT, not just the two known offenders: a pin on one pair would say nothing
    # about the next one. The select is asserted present as well, because the honest fix here was to
    # rename the hidden field rather than to stop rendering the form — that the confirm step shows
    # the OLD cadence in that select is a separate, open design question (spec §10.6 item 5).
    it "renders no duplicate element ids", :aggregate_failures do
      ids = page.all("[id]", visible: :all).pluck(:id).compact_blank

      expect(ids).to eq(ids.uniq)
      expect(page).to have_css("select#user_period_cadence", visible: :all, count: 1)
      expect(page).to have_css("#pending_period_cadence", visible: :all, count: 1)
    end

    # BOTH HALVES OF THE ANSWER LAND TOGETHER (§3.5: one confirm, one transaction). The cadence AND
    # the amount are asserted on each arm, because a screen that wrote one without the other is
    # exactly the half-changed state the transaction exists to prevent.
    it "scales the rules when that is the answer", :aggregate_failures do
      click_button "Scale them"

      expect(page).to have_content("your per-period amounts were scaled to it")
      expect(user.reload.period_cadence).to eq("biweekly")
      expect(user.all_budgets.sole.amount).to eq(BigDecimal("184.62"))
      within(rule_row("Groceries")) { expect(page).to have_content("$184.62 / period") }
    end

    it "keeps the amounts when that is the answer", :aggregate_failures do
      click_button "Keep amounts"

      expect(page).to have_content("Your period and income are saved")
      expect(user.reload.period_cadence).to eq("biweekly")
      expect(user.all_budgets.sole.amount).to eq(400)
      within(rule_row("Groceries")) { expect(page).to have_content("$400.00 / period") }
    end
  end

  # ** A RULE STATED IN CALENDAR TIME IS NOT OFFERED, AND THE PAIR IS THE POINT. ** "$260 a month"
  # already means the same thing on every grid — `Budget#steady_ask` is what divides it by the
  # cadence — so scaling it here would apply the ratio twice and leave the user asking for 8 cents
  # in the dollar of what they said. The per-period rule beside it IS listed, on the same screen at
  # the same moment, so a confirm that simply listed nothing would fail this too.
  describe "changing the period with a monthly-basis rate beside a per-period one" do
    it "offers only the rule whose amount is denominated in periods", :aggregate_failures do
      rate(holder("Groceries", priority: 1), 400)
      create(:budget, :rate, category: holder("Phone", priority: 2), amount: 260)
      visit budget_page_path

      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      expect(page).to have_css("[data-cadence-line='Groceries']")
      expect(page).to have_no_css("[data-cadence-line='Phone']")
    end
  end

  # ** EVERY RULE DENOMINATED PER PERIOD SCALES, WHATEVER ITS CATEGORY'S SHAPE (fix round MED-3). **
  # The offer used to require `ClaimCalculator#rate?`, which is a question about the CATEGORY — a
  # $150-a-period rule on a $1,200 goal is shape `:target`, so it was silently left behind while
  # the identical rule on a category with no target was scaled. `Budget#steady_ask` is what settles
  # this: its `:per_period` branch takes the amount VERBATIM per period, so the grid is exactly
  # what that rule's cost depends on. A dated bill on the same screen is not offered — it names an
  # occurrence, and the catch-up formula re-plans it on whatever grid exists — so a confirm that
  # simply listed every rule would fail this too.
  #
  # $150 × 12 ÷ 26 = $69.2307…, which rounds to $69.23.
  describe "changing the period with a per-period rule on a goal beside a dated bill" do
    before do
      rate(holder("Vacation", priority: 1, target: 1_200), 150)
      create(
        :budget,
        category: holder("Car Insurance", priority: 2),
        amount: 1_200,
        interval_months: 6,
        anchor_date: Date.current + 3.months
      )
      visit budget_page_path

      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"
    end

    it "offers the goal's per-period rule and not the dated bill", :aggregate_failures do
      within("[data-cadence-line='Vacation']") do
        expect(page).to have_css("[data-cadence-now]", text: "$150.00")
        expect(page).to have_css("[data-cadence-scaled]", text: "$69.23")
      end
      expect(page).to have_no_css("[data-cadence-line='Car Insurance']")
    end

    it "scales it and leaves the dated bill's amount alone", :aggregate_failures do
      click_button "Scale them"

      expect(page).to have_content("your per-period amounts were scaled to it")
      expect(user.all_budgets.find_by(basis: :per_period).amount).to eq(BigDecimal("69.23"))
      expect(user.all_budgets.find_by(interval_months: 6).amount).to eq(1_200)
    end
  end

  # THE CADENCE HAS TO ACTUALLY MOVE. Editing the income on a user who keeps their period must not
  # produce a question about amounts nothing is changing the meaning of — the offer is keyed on the
  # cadence and not on the form having been submitted.
  describe "saving the declaration without touching the period" do
    it "asks nothing and saves the income", :aggregate_failures do
      rate(holder("Groceries"), 400)
      visit budget_page_path

      fill_in "You typically bring in", with: "5000"
      click_button "Save period and income"

      expect(page).to have_content("Your period and income are saved")
      expect(page).to have_no_css("[data-cadence-confirm]")
      expect(user.reload.typical_income).to eq(5_000)
    end
  end

  # ** A FIRST CADENCE IS NOT A CHANGE. ** Until the user names a period their per-period amounts
  # are denominated in nothing they said — `User#periods_per_year` falls back to 12 as an
  # assumption, not as a statement — so there is no old unit to convert from and the app asks
  # nothing. The rule's amount is asserted UNCHANGED as well as the absent panel: an offer silently
  # taken would show up here as $184.62.
  describe "declaring a period for the first time" do
    it "saves it without asking, and touches no amount", :aggregate_failures do
      user.update!(period_cadence: nil, period_anchor_date: nil)
      rate(holder("Groceries"), 400)
      visit budget_page_path

      select "Biweekly", from: "How long is a period?"
      fill_in "A day a period starts", with: Date.current.strftime("%Y-%m-%d")
      click_button "Save period and income"

      expect(page).to have_no_css("[data-cadence-confirm]")
      expect(user.reload.period_cadence).to eq("biweekly")
      expect(user.all_budgets.sole.amount).to eq(400)
    end
  end

  # ** THE ERROR COMES FIRST. ** A cadence with no anchor is refused by `User`, and a confirm in
  # front of it would ask the user about amounts, take their answer, and only then tell them the
  # period could not be saved at all. The question is only asked about a declaration that would
  # actually land.
  describe "a cadence change the declaration itself refuses" do
    it "shows the refusal rather than the offer", :aggregate_failures do
      rate(holder("Groceries"), 400)
      visit budget_page_path

      select "Biweekly", from: "How long is a period?"
      fill_in "A day a period starts", with: ""
      click_button "Save period and income"

      expect(page).to have_css("[data-declaration-error]")
      expect(page).to have_no_css("[data-cadence-confirm]")
      expect(user.reload.period_cadence).to eq("monthly")
    end
  end

  # NOTHING TO SCALE, NOTHING TO ASK. A dated bill is time-proportional — the catch-up formula
  # re-plans on whatever grid exists — so a user whose only rule is one meets no confirm step at
  # all. The negative assertion is the subject: an offer here would be two buttons over an empty
  # list.
  describe "changing the period with no rate rules" do
    before do
      create(
        :budget,
        category: holder("Car Insurance"),
        amount: 1_200,
        interval_months: 6,
        anchor_date: Date.current + 3.months
      )
      visit budget_page_path
    end

    it "saves straight away with no question", :aggregate_failures do
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      expect(page).to have_content("Your period and income are saved")
      expect(page).to have_no_css("[data-cadence-confirm]")
      expect(user.reload.period_cadence).to eq("biweekly")
    end
  end

  # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE — Chrome refuses to make a
  # headless window narrower than 500px, so every window-based spelling of this is a 500px test
  # wearing a 375 label. `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is
  # what CSS media queries read. (See `home/hero_spec.rb`, where this idiom and the reason for it
  # were measured.)
  #
  # THE PANEL IS THE WIDEST NEW THING ON THIS PAGE: two fields, two buttons and a skip whose label
  # carries a money figure. `flex-wrap` is what keeps it inside the card, and the assertion is
  # Selenium's own geometry rather than a JS `scrollWidth` — a trailing `evaluate_script` is what
  # `home/hero_spec.rb` measured as the cause of its own InvalidSessionIdError.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    it "keeps the open panel and its buttons inside a 375px viewport", :aggregate_failures do
      rate(holder("Vacation", target: 1_200), 150)
      visit budget_page_path
      open_adjust("Vacation")

      panel = find("[data-adjust='Vacation']").native.rect
      skip = find("[data-adjust='Vacation'] [data-adjust-skip]").native.rect

      expect(panel.x + panel.width).to be <= 375
      expect(skip.x + skip.width).to be <= panel.x + panel.width
    end
  end
end
