# frozen_string_literal: true

require "rails_helper"

# THE §6 IMPACT CARD ON THE ENTRY FORM — the daily screen learning to answer "can I afford this".
#
# THIS SUITE IS THE CLIENT/SERVER AGREEMENT. `EntryImpactPresenter`'s own spec pins what the server
# says; every figure here is read out of a real browser after real typing, against the SAME planted
# literals, so a subtraction that diverges between Ruby and JavaScript fails on one side or the
# other rather than agreeing quietly on a wrong number.
#
# `Capybara.exact` is unset in this suite, so every figure is scoped to its own `data-figure` inside
# the card. Unscoped, "$240.00" would match the balance from an assertion about the balance-after
# and a swapped pair would pass.
#
# EVERY FIXTURE IS BIWEEKLY and every category is funded by an ALLOCATION whose amount is spelled
# out here (two-ledger spec §2 — a category holds its own money and an allocation is what puts it
# there). A monthly rule's amount and its per-period claim are never the same number — the
# mixed-unit slip has struck five times on this branch.
RSpec.describe "Entry impact card", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  # `let!` AND FIRST, so this is the account the `:account` trait nominates as main — a category
  # minted before it would pull the factory's own account into being and claim the nomination,
  # leaving the income category below pointing at an account that is not main.
  # rubocop:disable RSpec/LetSetup -- nothing NAMES this account and every example needs it:
  # the `:account` trait's `after(:create)` is what makes the user's first account their MAIN
  # one, and the pot is where every entry below lands.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  # THE DAY EVERY CATEGORY HERE STARTED HOLDING MONEY, a year back, so an entry dated today or
  # yesterday counts against it.
  let(:funded_since) { Date.current - 1.year }

  # $240 in the category against a $300-a-period claim — the spec's own mockup, to the dollar.
  let!(:groceries) do
    create(:category, :expense, user: user, name: "Groceries", funded_since: funded_since).tap do |category|
      create(:allocation, kind: :allocation, to_category: category, amount: 240, date: Time.zone.now)
      create(:budget, :per_period_rate, category: category, amount: 300)
      create(:item, category: category, name: "Weekly shop")
    end
  end

  # THE TWO CATEGORIES EVERY OTHER STATE NEEDS, reached by name through the select rather than by
  # reference: an expense that is NOT HOLDING MONEY — no `funded_since`, so its spending drains
  # available (§4's start-date rule), which is what "unbudgeted" means now — and an income one
  # (which must land in an account, `Category#income_must_land_in_an_account`).
  before do
    create(:category, :expense, user: user, name: "Shopping")
    create(:category, user: user, name: "Paycheck", category_type: :income)
    sign_in user, scope: :user
  end

  # PICKING A CATEGORY THE WAY A USER DOES, and THE CONTROL RATHER THAN THE INPUT INSIDE IT. `entries/form_spec.rb` clicks `#category_id-ts-control`
  # directly and that works on a NEW entry only: TomSelect adds `input-hidden` to a wrapper whose
  # select already has a value, which sets that input to `opacity: 0` — invisible to Capybara — so
  # on every edit page the click cannot land. Measured, after a stable first failure: the wrapper
  # reads `class="ts-wrapper form-select single input-hidden has-items"` and the input's computed
  # opacity is 0 while its box is still 716×20. The parent `.ts-control` is what a user clicks in
  # both states.
  #
  # The wait is explicit and longer than the default because TomSelect is what builds this control,
  # and on the first page of a freshly launched browser it has been measured taking longer than the
  # 5-second default to get there — a stable-looking failure with an unstable cause.
  def select_category(name)
    expect(page).to have_css("#category_id-ts-control", visible: :all, wait: 10)
    find("#category_id-ts-control", visible: :all).find(:xpath, "..").click
    find("#category_id-ts-dropdown .option", text: name).click
  end

  def card = find("[data-impact-card]")

  def figure(name) = find("[data-figure='#{name}']")

  # THE DAY THE PERIOD RUNS TO, re-derived here rather than read off the presenter: a biweekly
  # period anchored on today closes on the thirteenth day after it, the day before the next edge.
  def period_end_label = (Date.current + 13).strftime("%b %-d")

  describe "an envelope the spending fits inside" do
    before do
      visit new_entry_path
      select_category("Groceries")
    end

    it "opens on the envelope, its balance and the day the period runs to", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='envelope']")

      within(card) do
        expect(figure("envelope")).to have_text("Groceries envelope")
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("$240.00")
        expect(figure("period-end")).to have_text("until #{period_end_label}")
      end
    end

    # 240 of a 300-a-period claim.
    it "draws the bar at what is left over what the envelope claims from a period" do
      expect(page).to have_css("[data-figure='bar'][style*='width: 80%']")
    end

    it "says nothing about a status, in either vocabulary", :aggregate_failures do
      within(card) do
        expect(page).not_to have_text("on track")
        expect(page).not_to have_text("behind")
        expect(page).not_to have_text("left to spend")
      end
    end

    it "subtracts what is typed and redraws the bar", :aggregate_failures do
      fill_in "Amount", with: "55"

      within(card) do
        expect(figure("balance-after")).to have_text("$185.00")
        expect(figure("balance")).to have_text("$240.00")
      end
      # 185 of 300.
      expect(page).to have_css("[data-figure='bar'][style*='width: 62%']")
    end

    it "follows the numpad, which types without a keyboard", :aggregate_failures do
      click_button "Calculator"
      click_button "5"
      click_button "5"

      expect(page).to have_field("Amount", with: "55")
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
    end

    # THE DIAL'S CLOSE-OUT MEASURED THIS: a value written into the box by something other than a
    # keystroke dispatches `change` and no `input` at all. A card listening only for `input` sits on
    # a stale figure, and the user never sees a keystroke that would wake it.
    it "follows a value set without a keystroke, which dispatches only change" do
      page.execute_script(<<~JS)
        const box = document.getElementById("entry_amount");
        box.value = "55";
        box.dispatchEvent(new Event("change", { bubbles: true }));
      JS

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
    end

    it "gives the whole envelope back when the amount is cleared", :aggregate_failures do
      fill_in "Amount", with: "55"
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }

      fill_in "Amount", with: ""

      within(card) { expect(figure("balance-after")).to have_text("$240.00") }
      expect(page).to have_css("[data-figure='bar'][style*='width: 80%']")
    end

    it "keeps the ordinary submit label and stays quiet about available", :aggregate_failures do
      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
      expect(page).not_to have_text("your available money covers the difference")
    end

    # `parseFloat("10*5")` is 10 and Dentaku says 50 on save. Neither belongs on the card, so it
    # holds at the balance until the formula resolves into a number.
    it "holds still for a formula and moves for the number it resolves to", :aggregate_failures do
      fill_in "Amount", with: "10*5"
      within(card) { expect(figure("balance-after")).to have_text("$240.00") }

      fill_in "Amount", with: "50"
      within(card) { expect(figure("balance-after")).to have_text("$190.00") }
    end
  end

  describe "overdrawing the envelope" do
    before do
      visit new_entry_path
      select_category("Groceries")
    end

    it "shows the envelope going negative, says available covers it, and does not block", :aggregate_failures do
      fill_in "Amount", with: "300"

      within(card) do
        expect(figure("balance-after")).to have_text("-$60.00")
        expect(figure("buffer")).to have_text("This envelope goes negative — your available money covers the difference.")
      end
      expect(page).to have_button("Save anyway")
      expect(page).not_to have_button("Create Entry")
      # `visible: :all` because an empty bar is a zero-width box, which Capybara counts as
      # invisible — the assertion is about the width itself.
      expect(page).to have_css("[data-figure='bar'][style*='width: 0%']", visible: :all)
    end

    it "puts everything back when the amount comes back inside the envelope", :aggregate_failures do
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
      expect(page).not_to have_text("your available money covers the difference")
    end

    # THE SACRIFICE DIAL'S SHIPPED BUG, in the one place it is reachable here: spending an envelope
    # to the exact penny is level, not negative, and `Intl.NumberFormat().format(-0)` is "-$0.00".
    it "reads level, not negative, when the envelope is spent to the penny", :aggregate_failures do
      fill_in "Amount", with: "240"

      within(card) do
        expect(figure("balance-after")).to have_text("$0.00")
        expect(figure("balance-after")).to have_no_text("-$0.00")
      end
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end

    it "still saves, because nothing blocks", :aggregate_failures do
      find("#entry_item_id-ts-control").click
      find("#entry_item_id-ts-dropdown .option", text: "Weekly shop").click
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      click_button "Save anyway"

      expect(page).to have_content("Entry was successfully created")
      expect(Entry.count).to eq(1)
      expect(Entry.last.amount).to eq(BigDecimal("300"))
    end
  end

  # A $1,500 balance reaches the browser as `data-balance`, and `parseFloat("1,500.00")` is 1.5 —
  # an envelope offering a dollar fifty. The delimiter is the defect and this is the example that
  # would catch it.
  describe "a category with four figures in it" do
    before do
      rent = create(:category, :expense, user: user, name: "Rent", funded_since: funded_since)
      create(:allocation, kind: :allocation, to_category: rent, amount: 1_500, date: Time.zone.now)
      create(:budget, :per_period_rate, category: rent, amount: 1_500)

      visit new_entry_path
      select_category("Rent")
    end

    it "subtracts from fifteen hundred and not from one dollar fifty", :aggregate_failures do
      fill_in "Amount", with: "100"

      within(card) do
        expect(figure("balance")).to have_text("$1,500.00")
        expect(figure("balance-after")).to have_text("$1,400.00")
        expect(figure("balance-after")).to have_no_text("-$98.50")
      end
    end
  end

  describe "a category that is not holding money" do
    before do
      visit new_entry_path
      select_category("Shopping")
    end

    it "is told the truth and pointed at the Budget page", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='unbudgeted']")

      within(card) do
        expect(figure("headline")).to have_text("Not holding money yet — this spending isn't budgeted.")
        expect(page).to have_text("It comes out of what's available.")
        expect(page).to have_link("Give it a rule on the Budget page", href: budget_page_path)
      end
    end

    # THE CONTRIBUTION'S SENTENCE IS GONE FROM THE APP (plan 3, task 5) — this card had two arms
    # keyed on `EntryImpactPresenter#contribution?`, and the savings one is deleted with the type.
    # Kept as a page-wide negative rather than deleted with it: the copy and the `/pools/new` link
    # were real words on a real screen, and this is what says they are not still reachable from
    # some other branch.
    it "has no contribution arm left to fall into", :aggregate_failures do
      expect(page).to have_no_css("[data-unbudgeted-arm]")

      within(card) do
        expect(page).not_to have_text("No goal")
        expect(page).not_to have_text("The money stays in your buffer")
        expect(page).not_to have_link("Make a savings goal for it")
      end
    end

    it "shows no envelope figures at all", :aggregate_failures do
      expect(page).not_to have_css("[data-impact-card='envelope']")
      expect(page).not_to have_css("[data-figure='balance']")
      expect(page).not_to have_css("[data-figure='bar']")
    end

    it "cannot be overdrawn, whatever is typed", :aggregate_failures do
      fill_in "Amount", with: "99999"

      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end

    # THE DATED ARM, and it is new with the re-anchored start-date rule (§4): a category that DOES
    # hold money still sends a receipt dated before its `funded_since` to available, so the same
    # honest card renders for it. Both directions on one category, so the example is about the date
    # and nothing else.
    it "is the same card for a receipt dated before the category started holding", :aggregate_failures do
      early = create(:entry, item: groceries.items.first, amount: 45, date: funded_since - 1.day)

      visit edit_entry_path(early)

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      within(card) do
        expect(figure("headline")).to have_text("Not holding money yet — this spending isn't budgeted.")
      end
    end
  end

  # THE "a savings category with no goal behind it" DESCRIBE IS DELETED WITH THE ARM (plan 3, task
  # 5). Its two examples pinned the contribution card — "No goal — this contribution has nowhere to
  # land", "The money stays in your buffer", and a link to `/pools/new` — against a savings category
  # pointing at an account. There is no savings category, so there is nothing to select and one
  # honest card is left. The negative above is what keeps the deleted copy from creeping back.

  # An empty grey track beside "$240.00 left" would say "nothing left" an inch under a figure saying
  # otherwise, so an envelope with nothing to claim gets no bar at all.
  describe "a category with no rules on it" do
    before do
      gifts = create(:category, :expense, user: user, name: "Gifts", funded_since: funded_since)
      create(:allocation, kind: :allocation, to_category: gifts, amount: 240, date: Time.zone.now)

      visit new_entry_path
    end

    it "prints the figures and draws no bar", :aggregate_failures do
      select_category("Gifts")

      within(card) { expect(figure("balance")).to have_text("$240.00") }
      expect(page).not_to have_css("[data-figure='bar']", visible: :all)
    end

    it "draws one on a category that does claim something", :aggregate_failures do
      select_category("Groceries")

      within(card) { expect(figure("balance")).to have_text("$240.00") }
      expect(page).to have_css("[data-figure='bar']", visible: :all)
    end
  end

  describe "an income category" do
    before do
      visit new_entry_path
      select_category("Paycheck")
    end

    # §6 leaves income out on purpose: it lands in the account, and saying so introduces the buffer.
    it "gets no card at all, of either kind", :aggregate_failures do
      expect(page).to have_select("category_id", selected: "Paycheck")
      expect(page).not_to have_css("[data-impact-card]")
      expect(page).not_to have_text("No envelope")
    end
  end

  describe "changing the category" do
    before { visit new_entry_path }

    it "re-renders the card for whichever envelope the new category reaches", :aggregate_failures do
      select_category("Groceries")
      within(card) { expect(figure("envelope")).to have_text("Groceries envelope") }

      select_category("Shopping")
      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(page).not_to have_css("[data-impact-card='envelope']")

      select_category("Groceries")
      expect(page).to have_css("[data-impact-card='envelope']")
      within(card) { expect(figure("balance")).to have_text("$240.00") }
    end

    it "carries the typed amount across the change rather than forgetting it", :aggregate_failures do
      select_category("Groceries")
      fill_in "Amount", with: "55"
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }

      select_category("Shopping")
      expect(page).to have_css("[data-impact-card='unbudgeted']")

      select_category("Groceries")
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_field("Amount", with: "55")
    end

    it "drops the overdraw label with the envelope it belonged to", :aggregate_failures do
      select_category("Groceries")
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      select_category("Shopping")

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end
  end

  # THE GOAL ARM, KEYED ON THE CATEGORY (Task 6) AND ON THE CALCULATOR (Task 7). It asked
  # `Category#savings?` — a holder, with a target, carrying NO refill rule — and now asks
  # `HoldingCalculator#saving_toward_a_target?`, the CHROME level of the two-level classification:
  # a goal is a goal whatever refills it. Spending from a goal is still spending against a goal, so
  # the card takes the goal shape and measures against the target.
  describe "a savings goal" do
    before do
      vacation = create(
        :category,
        :expense,
        user: user,
        name: "Vacation",
        funded_since: funded_since,
        target_amount: 2_400
      )
      create(:allocation, kind: :allocation, to_category: vacation, amount: 600, date: Time.zone.now)

      visit new_entry_path
      select_category("Vacation")
    end

    it "takes the goal shape and subtracts what is spent", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='goal']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("envelope")).to have_text("Vacation goal")
        expect(figure("balance")).to have_text("$600.00")
        expect(figure("balance-after")).to have_text("$450.00")
        expect(figure("goal")).to have_text("of $2,400.00 goal")
      end
    end

    # THE ATTRIBUTE THE BROWSER USED TO MULTIPLY BY IS GONE. It carried +1 for a savings category,
    # and with one direction left it would be the constant -1 on every render.
    it "sends the browser no direction to decide", :aggregate_failures do
      expect(page).to have_no_css("[data-direction]")
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }
    end

    it "measures the bar against the goal", :aggregate_failures do
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }

      # 450 of 2,400.
      expect(page).to have_css("[data-figure='bar'][style*='width: 19%']")
      expect(page).not_to have_css("[data-figure='bar'][style*='width: 100%']")
    end

    # THE OTHER DIRECTION ON THE SURVIVING ARM: a goal CAN go negative, and it says so in the app's
    # ordinary overdraw vocabulary rather than being exempted from it.
    it "reads as the goal going negative when it is emptied", :aggregate_failures do
      fill_in "Amount", with: "5000"

      within(card) { expect(figure("balance-after")).to have_text("-$4,400.00") }
      expect(page).to have_button("Save anyway")
    end
  end

  # ** THE ANCHOR-DATED GOAL, PINNED AT THE BROWSER (fix round 1, MED-2). ** The two-level
  # classification's sharpest shape, and the one no screen tested: a goal whose rule names a DUE
  # DATE is `HoldingCalculator#dateless_goal?` FALSE — so Home's row calls it `on track` rather than
  # `saving` — while `#saving_toward_a_target?` is still true, so THIS card must keep drawing it as
  # a goal. The card speaks no status at all (see EntryImpactPresenter's header), so all that is
  # asked of it here is that the chrome level does not inherit the status level's condition.
  #
  # The same category is pinned on the holdings card
  # (`spec/system/categories/show/holdings_spec.rb`) and on Home's row
  # (`spec/system/home/categories_spec.rb`), which is what makes this a cross-screen agreement
  # rather than three files each describing their own fixture.
  describe "a goal whose rule carries a due date" do
    before do
      house = create(
        :category,
        :expense,
        user: user,
        name: "House Deposit",
        funded_since: funded_since,
        target_amount: 2_400
      )
      create(:allocation, kind: :allocation, to_category: house, amount: 600, date: Time.zone.now)
      create(
        :budget,
        category: house,
        amount: 300,
        interval_months: 1,
        anchor_date: Date.current + 2.months
      )

      visit new_entry_path
      select_category("House Deposit")
    end

    it "still takes the goal shape and still measures against the target", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='goal']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("envelope")).to have_text("House Deposit goal")
        expect(figure("goal")).to have_text("of $2,400.00 goal")
        expect(figure("balance-after")).to have_text("$450.00")
      end
    end
  end

  describe "editing an entry the ledger has already counted" do
    let!(:existing) do
      create(:entry, item: groceries.items.first, amount: 45, date: Date.current)
    end

    before { visit edit_entry_path(existing) }

    # The ledger says $195 — $240 funded less the $45 already logged. The card says $240, because
    # the question on the screen is what this entry costs, not what the last one did.
    it "opens on the world without this entry, then puts it back", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='envelope']")

      expect(groceries.holding_calculator.balance).to eq(BigDecimal("195"))
      within(card) do
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("$195.00")
      end
    end

    it "moves the right-hand figure as the amount is edited", :aggregate_failures do
      fill_in "Amount", with: "100"
      within(card) { expect(figure("balance-after")).to have_text("$140.00") }

      fill_in "Amount", with: "10"
      within(card) { expect(figure("balance-after")).to have_text("$230.00") }
    end

    # THE FIGURES DIFFER FROM THE CREATE CASE ON THE SAME ENVELOPE AND THE SAME AMOUNT, which is the
    # whole of what the exclusion is for.
    it "differs from logging the same amount as a new entry", :aggregate_failures do
      visit new_entry_path
      select_category("Groceries")
      fill_in "Amount", with: "45"

      within(card) do
        expect(figure("balance")).to have_text("$195.00")
        expect(figure("balance-after")).to have_text("$150.00")
      end
    end

    it "credits a different category with nothing when the category is changed", :aggregate_failures do
      dining = create(:category, :expense, user: user, name: "Dining Out", funded_since: funded_since)
      create(:allocation, kind: :allocation, to_category: dining, amount: 100, date: Time.zone.now)
      visit edit_entry_path(existing)

      select_category("Dining Out")

      within(card) do
        expect(figure("envelope")).to have_text("Dining Out envelope")
        expect(figure("balance")).to have_text("$100.00")
        expect(figure("balance-after")).to have_text("$55.00")
      end
    end
  end

  # ── DELETED (Task 6): "re-categorising spending inside one goal". It planted TWO categories —
  # Vacation and Education — pointing at ONE savings pool, so an entry re-categorised between them
  # stayed inside the same holding and the give-back still applied. Multi-category envelopes are
  # gone (two-ledger spec §5: one category, one budget line), so two categories cannot share a
  # holding and the shape has no successor. The give-back itself is pinned by "credits a different
  # category with nothing when the category is changed" directly above, which is the other half of
  # the same reader.

  describe "editing an entry that already overdraws its category" do
    let!(:existing) do
      create(:entry, item: groceries.items.first, amount: 300, date: Date.current)
    end

    it "opens on the negative figure and on 'Save anyway'", :aggregate_failures do
      visit edit_entry_path(existing)

      expect(page).to have_css("[data-impact-card='envelope']")
      within(card) do
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("-$60.00")
        expect(figure("buffer")).to be_visible
      end
      expect(page).to have_button("Save anyway")
      expect(page).not_to have_button("Update Entry")
    end

    it "goes back to the ordinary label once the amount fits", :aggregate_failures do
      visit edit_entry_path(existing)
      expect(page).to have_button("Save anyway")

      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Update Entry")
      expect(page).not_to have_button("Save anyway")
    end
  end
end
