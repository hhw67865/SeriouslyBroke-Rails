# frozen_string_literal: true

require "rails_helper"

# ** THE BUDGET PAGE IS THE LIST OF EVERY CATEGORY (two-shapes spec §4). ** One row each: a drag
# handle where the reorder can take it, the name, how many rules it carries, a dot per rule in its
# type's colour, what it claims — or, where nothing claims it, what has been spent there — a
# suggestion badge, and a chevron.
#
# ** IT IS THE SUCCESSOR OF `rules_spec.rb`'s "the fill order", "a rule whose category holds
# nothing yet", "a brand-new user" AND "the type overview" GROUPS. ** Those were statements about
# which rows the page draws and in what order, which is this file's subject; what a RULE says about
# itself stayed there, and the type overview's three figures are on the tile that replaced the line
# (`tiles_spec.rb`).
#
# `Capybara.exact` is unset in this suite, so every row assertion is scoped — an unscoped
# `have_content("Groceries")` matches the row, the rule inside it and the nav at once.
RSpec.describe "Budget page list", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end

  before { sign_in user, scope: :user }

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — `funded_since` is what makes `Category#holder?`
  # true, and it is what puts a category in the reorder's own population.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  def unfunded(name) = create(:category, :expense, user: user, name: name)

  def rate(category, amount, type: :usage)
    create(:budget, :per_period_rate, category: category, amount: amount, rule_type: type)
  end

  def row(name) = find("[data-category-row='#{name}']")

  # THE PARTS OF ONE ROW, BY THE HOOKS THAT NAME THEM — the layout examples measure three or four
  # of them against each other and against the card, and a `find(...).native.rect` line each says the
  # same thing three or four times.
  def row_rects(name, *selectors) = selectors.map { |selector| row(name).find(selector).native.rect }

  def rows = page.all("[data-category-row]").pluck("data-category-row")

  # A RULE THAT NAMES AN ITEM of its category — the lane a second rule on one category needs
  # (`Budget#category_may_hold_one_item_less_rule`).
  def lane_rule(category, item_name, amount:, type: :usage)
    create(
      :budget,
      :per_period_rate,
      category: category,
      item: create(:item, category: category, name: item_name),
      amount: amount,
      rule_type: type
    )
  end

  # A CATEGORY WITH SPENDING AND NO RULE — the shape the engine proposes a rate for, and the shape
  # whose row prints a window figure instead of a claim. Three periods of $150, fourteen days apart.
  def spender(name, amount: 150)
    create(:category, :expense, user: user, name: name).tap do |category|
      item = create(:item, category: category, name: "#{name} item")
      [42, 28, 14].each { |back| create(:entry, item: item, amount: amount, date: Date.current - back.days) }
    end
  end

  # A HOLDER WHOSE RULE NAMES AN ITEM, so no detector fires on it: drift measures item-LESS rate
  # rules only, and the dead-rule detector needs its item to have had entries. A plain rate rule on a
  # holder with no spending IS a drift suggestion, which is correct and would make a "no badge here"
  # assertion say nothing.
  def quiet_holder(name, priority: 1)
    holder(name, priority: priority).tap { |category| lane_rule(category, "#{name} item", amount: 400) }
  end

  describe "which rows the page draws, and in what order", :aggregate_failures do
    # ** THE ORDER IS PRIORITY — THE NUMBER THE ARROWS ON THESE ROWS WRITE (fix round MAJOR-1). **
    # For one commit it was the GIVE-WAY order, type first, and that list could not be dragged: the
    # type ranks before priority and no control here can reach it, so moving a card produced the same
    # order under a flash saying it had changed. The same three categories read `[Fun, Groceries,
    # Rent]` in give-way order — asserted here off HOME, so the two screens are pinned as two
    # readings of ONE set of rows rather than one of them being wrong.
    it "puts the categories in priority order, where Home puts them in give-way order", :aggregate_failures do
      rate(holder("Rent", priority: 1), 900, type: :bill)
      rate(holder("Groceries", priority: 5), 400, type: :usage)
      rate(holder("Fun", priority: 9), 100, type: :choice)

      visit budget_page_path
      expect(rows).to eq(["Rent", "Groceries", "Fun"])

      visit root_path
      expect(page.all("[data-category-block]").pluck("data-category-block")).to eq(["Fun", "Groceries", "Rent"])
    end

    # ** EVERY EXPENSE CATEGORY IS ON THE PAGE, RULE-LESS ONES AFTER THE RULED ONES, BY NAME. ** The
    # old page drew a card only for a holder that carried a rule; a category nobody has written a
    # rule for is exactly where the next rule goes, and omitting it sent that user hunting.
    it "lists rule-less categories after the ruled ones, by name" do
      rate(holder("Groceries"), 400)
      holder("Zoo")
      unfunded("Aquarium")

      visit budget_page_path

      expect(rows).to eq(["Groceries", "Aquarium", "Zoo"])
    end

    # ** A RULE ON A CATEGORY THAT HOLDS NOTHING HAS A ROW, AND NO HANDLE. ** This is what deleted
    # the "not filling" band (§4/§7): it listed exactly these rules under a heading saying no group
    # could show them, and every expense category is in the list now. The handle is withheld because
    # `Category.apply_fill_order` refuses any list but `in_fill_order.with_a_rule` — a row with
    # arrows the endpoint rejects would be a control whose every use fails, with a message about the
    # order the page had just drawn.
    it "gives a rule on a category that holds nothing a row and no arrows" do
      # TWO HOLDERS, so the arrow the holder DOES get is enabled: with one draggable row both of its
      # arrows are at an end and disabled, and the pair below would read the same either way. The
      # list is PRIORITY order, so Rent (2) is the lower of the two and is the one that can move up.
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Rent", priority: 2), 900)
      rate(unfunded("Coffee"), 35)

      visit budget_page_path

      expect(rows).to include("Coffee")
      within(row("Coffee")) { expect(page).to have_no_button("Move Coffee up").and have_content("1 rule") }
      within(row("Rent")) { expect(page).to have_button("Move Rent up") }
    end

    # AN INCOME CATEGORY IS NOT ON THIS PAGE AT ALL — a rule cannot claim one
    # (`Budget#category_must_be_an_expense`), so a row for it would be a row with no rule it could
    # ever hold.
    it "leaves out income categories" do
      rate(holder("Groceries"), 400)
      create(:category, :income, user: user, name: "Salary")

      visit budget_page_path

      expect(rows).to eq(["Groceries"])
    end
  end

  describe "what one row says", :aggregate_failures do
    # ** A DOT PER RULE, IN THE RULE'S OWN TYPE — never the category's. ** A category may carry a
    # bill beside a choice and they give way at opposite ends of the walk, so a row painting one dot
    # per CATEGORY would be colouring the wrong thing. The colours are `HomeHelper::STRIPE_FILLS`,
    # the same table Home's stripes and the tiles' bands read.
    it "counts the rules and paints a dot per rule in its type" do
      groceries = holder("Groceries")
      rate(groceries, 400, type: :usage)
      lane_rule(groceries, "Wine", amount: 50, type: :choice)

      visit budget_page_path

      within(row("Groceries")) do
        expect(page).to have_content("2 rules")
        expect(page.all("[data-type-dot]").pluck("data-type-dot")).to eq(["choice", "usage"])
        expect(find("[data-type-dot='choice']")[:class]).to include("bg-terracotta")
        expect(find("[data-type-dot='usage']")[:class]).to include("bg-dusty-teal")
      end
    end

    # ** `$X claimed` IS Σ THE CATEGORY'S RULES' CLAIMS — the same figure `free` subtracted on Home
    # and the same one the header of the old group card printed. ** Planted: a $400 rate rule with
    # $250 spent this period claims `max(0, 400 − 250)` = $150.
    it "reads what the category claims" do
      groceries = holder("Groceries")
      rate(groceries, 400)
      create(:entry, item: create(:item, category: groceries), amount: 250, date: Date.current)

      visit budget_page_path

      within(row("Groceries")) { expect(page).to have_css("[data-category-claim]", text: "$150.00 claimed") }
    end

    # ** A RULE-LESS CATEGORY SAYS WHAT WAS SPENT, NOT WHAT IS CLAIMED (§4). ** Nothing claims this
    # money, so there is no claim to print; the figure is the suggestion engine's own window, which
    # is what keeps the sentence and the proposals beside it measured over the same periods.
    it "reads a rule-less category's recent spending instead" do
      spender("Coffee")

      visit budget_page_path

      within(row("Coffee")) do
        expect(page).to have_css("[data-category-spent]", text: "$450.00 spent in")
        expect(page).to have_no_css("[data-category-claim]")
      end
    end

    # NOTHING SPENT IS A SENTENCE AND NOT A ZERO: `$0.00 spent in 6 periods` is a figure pretending
    # to be a measurement, and a user with no cadence has no periods to have spent anything in.
    it "says nothing spent yet where the window is empty" do
      unfunded("Coffee")

      visit budget_page_path

      within(row("Coffee")) { expect(page).to have_css("[data-category-spent]", text: "nothing spent yet") }
    end

    # ** THE BADGE IS THE SUGGESTIONS INDEX'S SUCCESSOR (§4), and it counts THIS category's. ** Both
    # directions on one screen: the category the engine has something for wears one and the quiet
    # one does not, so a badge rendered unconditionally would fail the second half.
    # THE QUIET CATEGORY'S RULE IS ITEM-BACKED so nothing fires on it: drift measures item-LESS rate
    # rules only, and the dead-rule detector needs its item to have had entries. A plain rate rule on
    # a holder with no spending IS a drift suggestion ("averaged $0.00 for 4 periods"), which is
    # correct and would leave this example asserting nothing.
    it "badges only a category the engine has something for" do
      quiet_holder("Groceries")
      spender("Coffee")

      visit budget_page_path

      within(row("Coffee")) { expect(page).to have_css("[data-suggestion-badge]", text: "1 suggestion") }
      within(row("Groceries")) { expect(page).to have_no_css("[data-suggestion-badge]") }
    end
  end

  # ** THE ONE USER THIS PAGE HAS NOTHING TO DRAW FOR. ** The gate moved from "no rules" to "no
  # expense category at all": a user with categories and no rules is not empty — they have a row
  # apiece, each carrying its own "+ New rule for <category>" button, which is the screen the empty
  # frame used to stand in for.
  describe "a user with nowhere to put a rule", :aggregate_failures do
    it "offers a category rather than a rule" do
      visit budget_page_path

      expect(page).to have_css("[data-budget-empty]")
      expect(page).to have_content("No spending categories yet")
      expect(page).to have_no_css("[data-category-row]")
    end

    # THE OTHER DIRECTION, and it is the state the old empty screen got WRONG: a category with no
    # rule is a row with a door in it, not an empty page.
    it "draws a row for a category with no rule at all" do
      holder("Groceries")

      visit budget_page_path

      expect(page).to have_no_css("[data-budget-empty]")
      within(row("Groceries")) { expect(page).to have_css("[data-category-spent]") }
    end
  end

  # ** A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE — Chrome refuses a headless
  # window narrower than 500px, so every `resize_to(375, …)` in this suite is really a 500px test.
  # The mechanism is `spec/system/home/money_spec.rb`'s, copied deliberately rather than re-derived,
  # and there is NO `evaluate_script` in the example: a trailing JS call leaves the session in a
  # state Capybara's teardown navigation does not survive. **
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # §4: "375: tiles stack; rows keep handle · name · dots · claimed". Measured with Selenium's own
    # geometry rather than with a media-query read.
    #
    # ** THE THREE-DIFFERENT-TOPS ASSERTION WAS DELETED HERE AND REPLACED IN `tiles_spec.rb`
    # (mobile pass, 2026-09-06). ** Three tiles stacked measured 362px, which put the first row of
    # this list at y=659 — off a 667px screen, so a phone opening the Budget page saw the tiles and
    # no budget. Need spans the row now and the other two halve the line beneath it, which is a
    # statement about the tiles and belongs on the tiles' own file; what stays here is what this
    # file is about — that the row's parts are inside the viewport.
    # ** THE NAME IS THE LAST THING ON THE ROW THAT MAY BE CUT (mobile pass, 2026-09-06). ** The row
    # stacked into two lines at 375 but the ▲▼ pair rode on the FIRST of them, and two 44px targets
    # plus their gaps left 145px for the name: "Miscellaneous Expenses" was clipped by its own
    # `truncate`, measured on the demo. The arrows are a column of their own now and the name has
    # the width; `truncate` is `sm:` only, so below that it WRAPS.
    #
    # THE WRAP IS WHAT IS ASSERTED, and its spelling is the height of the heading's own box: a
    # truncated name is exactly one line tall whatever it says, so a `truncate` that came back would
    # fail this without a screenshot to read. The claim is then measured BELOW the name, which is
    # the two-line row §4 asks for, and the chevron is measured as a real target.
    # THE LONGEST NAME ON THE DEMO, which is where the clipping was found.
    let(:long_name) { "Utilities Monthly (Phone, Housing)" }

    it "keeps the row's four parts inside 375px", :aggregate_failures do
      rate(holder("Groceries"), 400)

      visit budget_page_path

      tiles = page.all("[data-tile]").map { |tile| tile.native.rect }
      claimed = find("[data-category-row='Groceries'] [data-category-claim]").native.rect
      dots = find("[data-category-row='Groceries'] [data-type-dots]").native.rect

      expect(tiles.map { |rect| rect.x + rect.width }).to all(be <= 375)
      expect(claimed.x + claimed.width).to be <= 375
      expect(dots.x + dots.width).to be <= 375
    end

    it "gives a long category name the line and wraps it rather than cutting it", :aggregate_failures do
      rate(holder(long_name), 400)

      visit budget_page_path

      card = row(long_name).native.rect
      name, claimed, chevron = row_rects(long_name, "h3", "[data-category-claim]", "[data-category-toggle]")

      expect(name.height).to be > 24
      expect(name.x + name.width).to be <= card.x + card.width
      expect(claimed.y).to be > (name.y + name.height) - 1
      expect(chevron.height).to be >= 40
      expect(chevron.x + chevron.width).to be <= card.x + card.width
    end
  end

  # ── THE BAND BETWEEN THE PHONE AND THE DESKTOP ─────────────────────────────────────────────────
  #
  # ** THE ROW'S TWO-LINE GRID HOLDS TO 768 AND NOT TO 640 (fix round, 2026-09-06). ** At `sm` the
  # one-line row came back at 640px, where it has 92px of arrows, three `gap-4`s and a `truncate` to
  # spend on a name — measured: "Utilities Monthly (Phone, Housing)" needs 231px and had 188. That
  # was true before this pass and 8px worse after it, so the breakpoint moved to `md`, where the row
  # has the width the desktop layout was drawn for.
  #
  # ** THE ASSERTION IS THE CLAIM'S POSITION AND NOT THE NAME'S HEIGHT. ** A wrap is what a
  # too-narrow column produces at 375; at 700 the grid gives the name 248px and it fits on ONE line,
  # so a height test here would fail on the fixed layout and pass on nothing. What tells the two
  # layouts apart at this width is the SHAPE: two lines with the claim under the name (grid) against
  # one line with the claim beside it (flex). The name's box being inside the card is what says it
  # was not cut to fit.
  describe "at 700px, between the phone and the desktop" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 700, height: 800, deviceScaleFactor: 1, mobile: false
      )
    end

    it "keeps the row on two lines and the long name whole", :aggregate_failures do
      rate(holder("Utilities Monthly (Phone, Housing)"), 400)

      visit budget_page_path

      card = row("Utilities Monthly (Phone, Housing)").native.rect
      name, claimed = row_rects("Utilities Monthly (Phone, Housing)", "h3", "[data-category-claim]")

      expect(claimed.y).to be > (name.y + name.height) - 1
      expect(name.width).to be > 200
      expect(name.x + name.width).to be <= card.x + card.width
    end
  end
end
