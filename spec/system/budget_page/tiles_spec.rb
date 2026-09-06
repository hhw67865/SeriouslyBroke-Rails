# frozen_string_literal: true

require "rails_helper"

# ** THE THREE TILES ACROSS THE TOP OF THE BUDGET PAGE (two-shapes spec §4) — what the rules need,
# what comes in, and the subtraction between them — and the declaration form behind the income
# tile's "change", which is still the first and only writer in the app for `typical_income`,
# `period_cadence` and `period_anchor_date`.
#
# ** SUCCESSOR OF `structural_check_spec.rb`. ** The check was a definition list under a heading
# asking "Does this fit your income?", with the form permanently open beneath it and the type
# overview a separate line above the groups; §4 makes them three tiles, and every figure and every
# gate below is the same one under a different hook (`data-tile` for `data-figure`, and the block's
# own `data-structural-check` gone with the block). The type overview's three totals arrived with
# them, off `rules_spec.rb`'s deleted group.
#
# `Capybara.exact` is unset in this suite, so every figure assertion is scoped to its own tile:
# unscoped, "$2,400.00 a period" matches the income tile from inside the need tile and a swapped
# pair of labels would pass.
RSpec.describe "Budget page tiles", type: :system do
  let(:user) { create(:user) }

  before { sign_in user, scope: :user }

  def tiles = find("[data-tiles]")

  def tile(name) = find("[data-tile='#{name}']")

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built here in the pool
  # era. Every figure this block prints is `Budget.steady_need`, which reads the RULE and never its
  # owner, so the conversion moves no number on the page.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  # ** THE FORM IS BEHIND "change" NOW (§4), so declaring starts by asking for it. ** It was
  # permanently open under a paragraph of prose, which put a three-field settings form in the middle
  # of the one screen that is about rules; `?declare=1` is what the tile's link carries and what a
  # refused submission comes back with.
  def open_declaration = visit(budget_page_path(declare: 1))

  def declare(income:, cadence:, anchor:)
    fill_in "You typically bring in", with: income
    select cadence, from: "How long is a period?"
    fill_in "A day a period starts", with: anchor
    click_button "Save period and income"
  end

  # A user who has declared a period, so the figures below have a unit.
  def declared_user(income)
    user.update!(typical_income: income, period_cadence: :biweekly, period_anchor_date: Date.current)
  end

  # STATE ONE OF THREE: nothing declared. The block invites rather than reports, and there is no
  # button — a comparison nobody has made cannot have an answer.
  describe "before anything is declared", :aggregate_failures do
    before do
      rate(holder("Rent"), 3_000)
      visit budget_page_path
    end

    # ** NOT YET SAID IS NOT ZERO. ** Zero is a claim about the user's income; this is the absence
    # of one, and the tile invites rather than reporting — which is the same distinction
    # `#typical_income`'s nil makes on the presenter.
    it "invites a declaration instead of printing figures" do
      within(tile("income")) { expect(page).to have_content("Not said yet") }
      within(tile("leftover")) { expect(page).to have_content("Declare your income") }
      expect(page).to have_no_content("Left over $")
    end

    it "shows no sacrifice button" do
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    # ** THE FORM IS BEHIND THE TILE'S OWN LINK (§4), and both directions are one example: hidden
    # until asked for, and complete when it arrives. ** Permanently open, it was a settings form in
    # the middle of the one screen that is about rules.
    it "hides the three fields until the tile's link is followed" do
      expect(page).to have_no_field("You typically bring in")

      # TWO TILES OFFER THE SAME DOOR — the income tile and the leftover tile, deliberately, because
      # a user reading either one is asking the same question — so the click is scoped to one.
      within(tile("income")) { click_link "Declare your income" }

      expect(page).to have_field("You typically bring in")
      expect(page).to have_select("How long is a period?")
      expect(page).to have_field("A day a period starts")
    end
  end

  # THE TILES ARE OUTSIDE THE EMPTY STATE, deliberately. A user who has declared nothing is usually
  # a user who has made nothing, and putting them inside the empty branch would leave the only
  # writer in the app for these three columns unreachable until they had built something first.
  describe "a brand-new user with nothing at all", :aggregate_failures do
    before { open_declaration }

    it "still gets the tiles and the form beside the empty state" do
      expect(page).to have_content("No spending categories yet")
      expect(page).to have_css("[data-tiles]")
      expect(page).to have_field("You typically bring in")
      expect(page).to have_button("Save period and income")
    end
  end

  # ** THE TYPE OVERVIEW IS THE NEED TILE'S BAR AND ITS THREE TOTALS (§4). ** It was a line of its
  # own above the groups (`rules_spec.rb`'s deleted "the type overview" group); the figures are the
  # same `ClaimCalculator#standing_ask` sums, which is what makes them add up to the tile above
  # them rather than to something near it.
  describe "the type split on the need tile", :aggregate_failures do
    before do
      declared_user(2_400)
      create(:budget, :per_period_rate, category: holder("Rent", priority: 1), amount: 1_000, rule_type: :bill)
      create(:budget, :per_period_rate, category: holder("Insurance", priority: 2), amount: 400, rule_type: :bill)
      create(:budget, :per_period_rate, category: holder("Groceries", priority: 3), amount: 600, rule_type: :usage)
      create(:budget, :per_period_rate, category: holder("Fun", priority: 4), amount: 300, rule_type: :choice)
      visit budget_page_path
    end

    # THE SPEC'S OWN LINE, to the character: two bills summing to $1,400.00, and the three read in
    # order of how unavoidable they are.
    it "states what each kind of rule asks of a period, heaviest first" do
      within(tile("need")) do
        expect(page).to have_content("Bills $1,400.00")
        expect(page).to have_content("Usage $600.00")
        expect(page).to have_content("Choice $300.00")
        expect(page).to have_content("$2,300.00 a period")
      end
      expect(tile("need").text).to match(/Bills.*Usage.*Choice/m)
    end

    # ** THE BAR IS THE SAME SPLIT IN THE SAME COLOURS THE ROWS' DOTS USE. ** One band per kind, its
    # width its share of the figure above it — so the bands add to the total and not to something
    # near it, and a bill is the same colour here, on a row's dot and on Home's stripe.
    it "draws one band per kind, in the type's own colour" do
      within(tile("need")) do
        expect(page.all("[data-type-band]").pluck("data-type-band")).to eq(["bill", "usage", "choice"])
        expect(find("[data-type-band='bill']")[:class]).to include("bg-brand-darker")
        expect(find("[data-type-band='bill']")[:style]).to include("61%")
      end
    end

    # A TYPE WITH NO RULES IS ABSENT, NOT $0.00 — a figure that is true and reports nothing, on a
    # line whose whole job is the split. The example above is the other direction.
    it "omits a kind no rule carries" do
      user.all_budgets.where(rule_type: :bill).destroy_all
      visit budget_page_path

      within(tile("need")) do
        expect(page).to have_content("Usage $600.00")
        expect(page).to have_no_content("Bills")
        expect(page).to have_no_css("[data-type-band='bill']")
      end
    end
  end

  # STATE TWO OF THREE: declared and covered. Figures, no button.
  describe "when the rules fit the income", :aggregate_failures do
    before do
      declared_user(2_400)
      rate(holder("Groceries"), 400)
      create(:budget, :rate, category: holder("Utilities", priority: 2), amount: 260)
      visit budget_page_path
    end

    # $400 a period passes straight through; $260 a month under a biweekly period is $120, NOT
    # $260 — the mixed-unit figure the rate normalisation exists to get right, asserted on the
    # rendered page rather than only in the model.
    # $400 a period passes straight through; $260 a month under a biweekly period is $120, NOT
    # $260 — the mixed-unit figure the rate normalisation exists to get right, asserted on the
    # rendered page rather than only in the model.
    #
    # ** THE THIRD TILE SAYS THE DIRECTION IN WORDS AND IN COLOUR (§4). ** "$1,880.00 free" became
    # the figure in green with "Your rules fit what you bring in" under it: the word "free" was
    # doing the work of a state, and a state is what the tile is for.
    it "prints the three figures from the spec" do
      within(tile("need")) { expect(page).to have_content("$520.00 a period") }
      within(tile("income")) { expect(page).to have_content("$2,400.00 a period") }
      within(tile("leftover")) do
        expect(page).to have_content("$1,880.00")
        expect(page).to have_css("[data-tile-verdict]", text: "Your rules fit what you bring in")
        expect(find("[data-tile-figure]")[:class]).to include("text-status-success")
      end
    end

    # AND THE CADENCE IS ON THE INCOME TILE, because "$2,400.00 a period" at a user who has not said
    # how long a period is has no unit — the same gate `#declared?` applies to the whole trio.
    it "names the cadence beside the income" do
      within(tile("income")) { expect(page).to have_css("[data-tile-cadence]", text: "Biweekly") }
    end

    it "shows no sacrifice button and does not call the budget underwater" do
      expect(page).to have_no_css("[data-sacrifice-link]")
      within(tiles) { expect(page).to have_no_content("Underwater") }
    end

    # THE CAPS NOTE IS GONE FROM THE PAGE (plan 3, task 3), so this asserts its absence rather than
    # the conditions it used to appear under. Two examples stood here: one planted a $650 cap and
    # checked that neither the figure nor the block mentioned it, and one gave a user caps and
    # nothing else so the block explained its own $0.00. A rule owned by a category is not a shape
    # the app can hold, so both fixtures are unbuildable and both examples are deleted with the
    # behaviour. What survives is the guarantee the note's deletion has to keep: nothing on this
    # page still talks about caps.
    it "says nothing about category caps anywhere" do
      expect(page).to have_no_css("[data-caps-note]")
      within(tiles) { expect(page).to have_no_content("spending limits") }
    end

    # ** THE BLOCK ITSELF IS GONE (§4/§7), and its heading with it. ** The three lines are three
    # tiles; a surviving "Does this fit your income?" panel would be the same three figures said
    # twice on one screen, in two places free to disagree.
    it "renders no structural-check block at all" do
      expect(page).to have_no_css("[data-structural-check]")
      expect(page).to have_no_content("Does this fit your income?")
    end
  end

  # ZERO NEED IS NOW THE BRAND-NEW USER AND NOTHING ELSE. It used to be the legacy shape too —
  # caps and no funding rules — which is what the deleted note explained.
  describe "a declared user with no rules at all", :aggregate_failures do
    before do
      declared_user(2_400)
      visit budget_page_path
    end

    it "reads zero with no explanation to give" do
      within(tile("need")) { expect(page).to have_content("$0.00 a period") }
      within(tile("leftover")) { expect(page).to have_content("$2,400.00") }
      expect(page).to have_no_css("[data-caps-note]")
    end

    it "is covered rather than underwater, and offers no cut list" do
      expect(page).to have_no_css("[data-sacrifice-link]")
      within(tiles) { expect(page).to have_no_content("Underwater") }
    end
  end

  # STATE THREE OF THREE: declared and underwater. Figures AND the button.
  #
  # GENUINELY UNDERWATER ON STEADY NEED, not on catch-up: a flat $3,000-a-period rule against
  # $2,400 of income is broken on every period there will ever be.
  describe "when the rules outrun the income", :aggregate_failures do
    before do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)
      visit budget_page_path
    end

    # ** THE THIRD TILE GOES RED AND SAYS WHICH WAY IT WENT. ** It printed the word "Underwater"
    # beside a positive figure; the tile prints the SIGNED leftover in red with the sentence under
    # it, which is one number rather than a figure and a label that could contradict it.
    it "states the gap in red, and says which way it went" do
      within(tile("need")) { expect(page).to have_content("$3,000.00 a period") }
      within(tile("leftover")) do
        expect(page).to have_content("-$600.00")
        expect(page).to have_css("[data-tile-verdict]", text: "Your rules ask for more than you bring in")
        expect(find("[data-tile-figure]")[:class]).to include("text-status-danger")
        expect(page).to have_no_content("buffer")
      end
    end

    # The button points at Task 9's sacrifice view, which is not routed yet. The link's presence
    # and its target are what this task owns; that the target answers is Task 9's.
    it "offers the way out" do
      expect(page).to have_css("[data-sacrifice-link]")
      # `end_with`, because the driver hands back an absolute URL with the test server's port in
      # it — the path is the part this task owns.
      expect(find("[data-sacrifice-link]")[:href]).to end_with("/sacrifice")
      expect(page).to have_link("What could you cut?")
    end
  end

  # THE CASE AMENDMENT A EXISTS FOR. A $5,200 annual premium falling due in three days asks for
  # all $5,200 out of THIS period — but its standing claim is $200 a period against $2,400 of
  # income, and nothing about that budget is structurally broken. The old reader compared this
  # period's ask and would have shown the button here.
  describe "a catch-up period on a budget that fits", :aggregate_failures do
    before do
      declared_user(2_400)
      create(
        :budget,
        category: holder("Car Insurance"),
        amount: 5_200,
        interval_months: 12,
        anchor_date: Date.current + 3.days
      )
      visit budget_page_path
    end

    it "reads the standing claim, not this period's ask" do
      within(tile("need")) do
        expect(page).to have_content("$200.00 a period")
        expect(page).to have_no_content("$5,200.00")
      end
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    # Both screens, one afternoon, one budget. Home's standing band reads the same redefined
    # figure, so a user cannot be told their budget fits on one page and does not on the other.
    it "does not warn on Home either" do
      visit root_path

      expect(page).to have_no_content("Your budget doesn't fit your income")
    end
  end

  # ** THE CHECK AND THE ROW ARE ONE PAGE AND USED TO CONTRADICT EACH OTHER (fix wave — MED-3). **
  # `Budget#steady_ask`'s one-off branch built a `BudgetCalculator`, whose `#fulfilled?` has NO
  # payment signal for an item-less rule and falls back to "assume every bill was paid on time"
  # (`today >= anchor_date`). So a $600 bill anchored a month ago with nothing spent was priced at
  # $0.00 a period by the block at the bottom of this page while its own row, an inch above, read
  # `overdue`. One rule, one afternoon, two verdicts.
  #
  # THE CLAIM HAS THE SIGNAL THAT CLASS LACKED — an item-less rule's fulfilment is spending on the
  # CATEGORY, which the walk already sums (§3.2) — so the two verdicts cannot part company again from
  # either side.
  #
  # ** RE-DERIVED ON `ClaimCalculator#standing_ask` (fix wave 2 — MED-A). ** The figure is the same
  # $600 and it is a different sentence: the wave between read §3.2's CATCH-UP share, which prices an
  # unpaid bill at its whole amount only because `#periods_left` floors at one — and therefore
  # changes the moment the bill is paid. The standing ask divides the amount by the periods from the
  # accrual start to the DUE DATE, and this rule was born today with its anchor a month behind it, so
  # there is no boundary between the two and the floor of one period is the honest divisor for as
  # long as the rule exists. Against $2,400 of income that is not underwater, which is the arm this
  # fixture is in.
  describe "an item-less one-off whose date has gone by unpaid", :aggregate_failures do
    let(:car_service) { holder("Car Service") }

    before do
      declared_user(2_400)
      create(
        :budget,
        category: car_service,
        amount: 600,
        interval_months: nil,
        anchor_date: Date.current - 1.month
      )
    end

    it "prices the bill the row calls overdue" do
      visit budget_page_path(open: car_service.id)

      within(tile("need")) do
        expect(page).to have_content("$600.00 a period")
        expect(page).to have_no_content("$0.00")
      end
      within("[data-rule='Car Service']") do
        expect(page).to have_css("[data-rule-when]", text: "overdue · was")
      end
    end

    # ** AND PAYING IT MOVES THE ROW, NOT THE VERDICT (fix wave 2 — MED-A). ** The same page after the
    # $600 has actually left the account: the rule's own row reads `$0.00 built up of $600.00` — the
    # fund emptied by the payment — while "your rules need" reads the same $600.00 a period, because
    # no rule changed. Under the catch-up reading the two moved TOGETHER and this line fell to $0.00,
    # which is a structural verdict a receipt could switch off. One page, one afternoon, two figures
    # that are supposed to answer different questions.
    it "keeps the same standing figure once the bill has been paid" do
      create(:entry, item: create(:item, category: car_service), amount: 600, date: Date.current)

      visit budget_page_path(open: car_service.id)

      # ** AND THE ROW NOW READS `paid <date>` RATHER THAN `overdue` (this task's carry (a)). ** A
      # one-time bill's occurrence never rolls, so the old reading called this paid bill late for
      # ever; the figure beside it is unchanged, because paying a fund is what empties it.
      within("[data-rule='Car Service']") do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $600.00")
        expect(page).to have_css("[data-rule-when]", text: "paid #{Date.current.strftime("%b %-d")}")
      end
      within(tile("need")) do
        expect(page).to have_content("$600.00 a period")
        expect(page).to have_no_content("$0.00")
      end
    end
  end

  # HOME'S TROUBLE STRIP, both directions. The branch has been unreachable in production since it
  # was written — there was no writer for `typical_income` — so this is the first time it renders
  # against a real user. It has moved twice since: the standing band became the hero card
  # (answers-first Task 1) and the button moved on to the trouble strip (Task 2), which is the right
  # home for a verdict that is only shown when it is true. The copy and the gate are unchanged, which
  # is why these two examples are untouched by either move.
  describe "Home's trouble strip", :aggregate_failures do
    it "warns when the budget does not fit" do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)

      visit root_path

      expect(page).to have_content("Your budget doesn't fit your income")
    end

    # THE TWO GATES ARE ONE GATE. `/budget` withholds its figures until income AND cadence exist,
    # because "$3,000.00 a period" at someone who has not said how long a period is states a
    # figure with no unit. Home used to gate on income alone, so the same user got the VERDICT
    # those figures justify without the figures — and the verdict was computed from
    # `steady_need`'s monthly fallback, a per-rule convenience that is not a reading of anyone's
    # budget.
    #
    # Both directions on one fixture, and the screens paired: with the cadence declared, Home
    # warns and `/budget` prints the figures; with it cleared, both fall silent together.
    it "says nothing when income is declared but no period is" do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)

      visit root_path
      expect(page).to have_content("Your budget doesn't fit your income")

      user.update!(period_cadence: nil, period_anchor_date: nil)

      visit root_path
      expect(page).to have_no_content("Your budget doesn't fit your income")

      visit budget_page_path
      within(tile("income")) { expect(page).to have_content("Not said yet") }
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    it "stays silent when it does" do
      declared_user(2_400)
      rate(holder("Groceries"), 400)

      visit root_path

      expect(page).to have_no_content("Your budget doesn't fit your income")
    end
  end

  # THE DECLARATION ITSELF, end to end: the figures on this page are computed from data that until
  # now only seeds could write.
  describe "declaring a period and an income", :aggregate_failures do
    before do
      rate(holder("Groceries"), 400)
      create(:budget, :rate, category: holder("Utilities", priority: 2), amount: 260)
      open_declaration
    end

    it "persists it and re-derives the block from it" do
      declare(income: "2400", cadence: "Biweekly", anchor: Date.current.strftime("%Y-%m-%d"))

      expect(page).to have_current_path(budget_page_path)
      within(tile("need")) { expect(page).to have_content("$520.00 a period") }
      within(tile("income")) { expect(page).to have_content("$2,400.00 a period") }
      expect(user.reload.period_cadence).to eq("biweekly")
    end

    # DECISION 6, and the reason the copy under the form says what it says: the same two rules,
    # the same income, a different period — and every figure moves. Under a monthly period the
    # $260-a-month rule claims its whole $260 and the $400-per-period rule is $400 of a month.
    #
    # ** THE SECOND SAVE NOW PASSES THROUGH §3.5'S OFFER (computed-claims Task 2), AND "KEEP
    # AMOUNTS" IS WHAT THIS EXAMPLE MEANS. ** The first declaration is a FIRST cadence and is never
    # asked about; the second moves a declared biweekly to monthly with a per-period rate rule on
    # the page, which is exactly the state the app now asks about. Keeping the amounts is what makes
    # this example's own claim true — the figures move because the PERIOD moved, with not a digit of
    # either rule touched — so the answer is part of the subject rather than a step around it. The
    # offer itself is pinned in `budget_page/adjustments_spec.rb`.
    it "re-derives every figure the moment the cadence changes" do
      declare(income: "2400", cadence: "Biweekly", anchor: Date.current.strftime("%Y-%m-%d"))
      within(tile("need")) { expect(page).to have_content("$520.00 a period") }

      # A SAVE REDIRECTS TO THE PAGE WITHOUT `declare`, so the form closes behind the user — which
      # is the affordance working: it is a settings form, and it is done. Changing the period again
      # is asking for it again, through the tile's own link.
      open_declaration
      select "Monthly", from: "How long is a period?"
      click_button "Save period and income"
      click_button "Keep amounts"

      within(tile("need")) { expect(page).to have_content("$660.00 a period") }
    end

    it "says so on the form" do
      expect(page).to have_content("Changing your period re-derives every figure immediately")
    end

    # A cadence with no anchor yields no boundaries at all, and the divisors downstream then clamp
    # to 1 — the app would demand whole bills out of the next period. `User` refuses it; the page
    # has to show the refusal rather than 500 or silently drop half the submission.
    it "refuses a period with no anchor, and writes nothing" do
      fill_in "You typically bring in", with: "2400"
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      expect(page).to have_css("[data-declaration-error]")
      within("[data-declaration-error]") { expect(page).to have_content("required when you set a period") }
      expect(user.reload.typical_income).to be_nil
      expect(user.reload.period_cadence).to be_nil
    end

    # A DEFECT THE BROWSER CAUGHT. A failed `update` leaves the rejected values on the in-memory
    # user, and the block was rendered from that object — so a refused submission printed "Your
    # rules need $520.00 a period / You typically bring in $2,400.00 / Left over $1,880.00 →
    # buffer" directly under the error saying nothing had been saved, and a page reload made all
    # three lines disappear. The figures now read the row; the form keeps what was typed.
    it "prints no figures it did not save, while keeping what was typed" do
      fill_in "You typically bring in", with: "2400"
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      within(tiles) do
        expect(page).to have_content("Not said yet")
        expect(page).to have_no_content("$2,400.00 a period")
      end
      # "2400.00", not "2400": the box renders the figure to two decimals now (design review,
      # nits) — a decimal column was printing `4000.0` into a money field whose placeholder says
      # `0.00`. The figure the user typed is unchanged, and that is what this example is about.
      expect(page).to have_field("You typically bring in", with: "2400.00")
      expect(page).to have_select("How long is a period?", selected: "Biweekly")
    end
  end

  # ── THE THREE TILES ON A PHONE ─────────────────────────────────────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE. Chrome refuses to make a
  # headless window narrower than 500px — `resize_to(375, 667)` and `--window-size=375,667` alike
  # report `width=500`, measured — so every window-based spelling of this is a 500px test wearing a
  # 375 label. `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is what CSS
  # media queries read. The idiom and the measurements behind it are in `home/money_spec.rb`, and
  # there is no trailing `evaluate_script` in either example below: Selenium's own geometry says
  # everything these assert, and a trailing JS call is what that file measured as the cause of its
  # own InvalidSessionIdError.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # ** NEED SPANS, INCOME AND LEFT OVER HALVE THE ROW BENEATH IT (mobile pass, 2026-09-06). **
    # Stacked one under the other the three tiles measured 362px tall and pushed the FIRST ROW OF
    # THE CATEGORY LIST to y=659 — off a 667px screen, so a phone opening this page saw three tiles
    # and no budget. The geometry IS the ruling: need is above both of the others and as wide as the
    # row; the two below share a top edge, split the width, and the subtraction reads left to right.
    #
    # `home/money_spec.rb` pins the same shape on Home's own three tiles, deliberately: one ruling,
    # two screens.
    it "spans the need tile and halves the other two inside a 375px viewport", :aggregate_failures do
      declared_user(2_400)
      rate(holder("Rent"), 1_000)

      visit budget_page_path

      need, income, leftover = ["need", "income", "leftover"].map { |name| tile(name).native.rect }
      figure = find("[data-tile='leftover'] [data-tile-figure]").native.rect

      expect(income.y).to be > (need.y + need.height) - 1
      expect(leftover.y).to eq(income.y)
      expect(leftover.x).to be > income.x
      expect([need, leftover].map { |rect| rect.x + rect.width }).to all(be <= 375)
      expect(figure.x + figure.width).to be <= leftover.x + leftover.width
    end

    # THE ONE DOOR ONTO THE DECLARATION, AND ON A PHONE IT HAS TO BE PRESSABLE. It measured 42×14 —
    # a fourteen-pixel target for the only control that can change the period every figure on this
    # page is divided by.
    it "gives the income tile's change link a box a finger can hit" do
      declared_user(2_400)

      visit budget_page_path

      expect(find("[data-declare-link]").native.rect.height).to be >= 40
    end
  end
end
