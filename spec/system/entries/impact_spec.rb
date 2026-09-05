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
# ** CONVERTED ONTO COMPUTED CLAIMS (spec §3). ** Every category here used to be funded by an
# ALLOCATION — money moved into it — and nothing moves (§5). The money is written the way the model
# actually produces it, and the figures on screen are the same figures:
#
#   $240 in Groceries    → a $300-a-period rule with $60 of it spent · `max(0, 300 − 60)`
#   $1,500 in Rent       → a $1,500-a-period rule with nothing spent
#   $600 in Vacation     → a $600-a-period rule on a $2,400 target, one period walked
#   $600 in House Deposit→ a $600 bill due inside this period, so the catch-up formula asks for the
#                          whole of it now (`periods_left` is 1) and the fund is whole
#   $240 in Gifts        → NOTHING. A category with no rules claims nothing (§3.4), which is the one
#                          figure on this screen that genuinely changed; see that example.
#
# EVERY FIXTURE IS BIWEEKLY. A monthly rule's amount and its per-period claim are never the same
# number — the mixed-unit slip has struck five times on this branch.
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

  # $240 claimed against a $300-a-period rule — the spec's own mockup, to the dollar, planted as
  # §3.1 makes it: the rate less what has been spent on the category this period. The $60 sits on an
  # item of its own so the "Weekly shop" item the editing examples write against stays empty until
  # they use it.
  let!(:groceries) do
    create(:category, :expense, user: user, name: "Groceries", funded_since: funded_since).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: 300)
      create(:item, category: category, name: "Weekly shop")
      create(:entry, item: create(:item, category: category, name: "Earlier shop"), amount: 60, date: Date.current)
    end
  end

  # The item the editing examples spend from, by NAME: the category carries two now, and
  # `items.first` is unordered.
  def weekly_shop = groceries.items.find_by(name: "Weekly shop")

  # THE TWO CATEGORIES EVERY OTHER STATE NEEDS, reached by name through the select rather than by
  # reference: an expense NO RULE CAN CLAIM — no `funded_since`, so its spending comes straight out
  # of free money (§4's start-date rule, computed-claims §2), which is what "unbudgeted" means now —
  # and an income one (which must land in an account, `Category#income_must_land_in_an_account`).
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
      expect(page).not_to have_text("comes straight out of what's free")
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
        expect(figure("buffer")).to have_text("This envelope goes over — the difference comes straight out of what's free.")
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
      expect(page).not_to have_text("comes straight out of what's free")
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
      # TWO: the fixture's own $60 receipt, which is what makes the claim $240, plus this one.
      expect(Entry.count).to eq(2)
      expect(Entry.where(amount: 300).count).to eq(1)
    end
  end

  # A $1,500 balance reaches the browser as `data-balance`, and `parseFloat("1,500.00")` is 1.5 —
  # an envelope offering a dollar fifty. The delimiter is the defect and this is the example that
  # would catch it.
  describe "a category with four figures in it" do
    before do
      rent = create(:category, :expense, user: user, name: "Rent", funded_since: funded_since)
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
        expect(figure("headline")).to have_text("Nothing claims this yet — this spending isn't budgeted.")
        expect(page).to have_text("It comes straight out of what's free.")
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
      early = create(:entry, item: weekly_shop, amount: 45, date: funded_since - 1.day)

      visit edit_entry_path(early)

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      within(card) do
        expect(figure("headline")).to have_text("Nothing claims this yet — this spending isn't budgeted.")
      end
    end
  end

  # THE "a savings category with no goal behind it" DESCRIBE IS DELETED WITH THE ARM (plan 3, task
  # 5). Its two examples pinned the contribution card — "No goal — this contribution has nowhere to
  # land", "The money stays in your buffer", and a link to `/pools/new` — against a savings category
  # pointing at an account. There is no savings category, so there is nothing to select and one
  # honest card is left. The negative above is what keeps the deleted copy from creeping back.

  # ** A FUNDED CATEGORY WITH NO RULES IS UNBUDGETED, ON THIS SCREEN AND ON HOME (fix round 1 —
  # M2). ** Gifts is funded a year back, so its spending DOES count against it the moment a rule
  # exists — but no rule does, and every claim comes from a rule (§3.3). It therefore has no
  # envelope, no figure and no bar, and the honest card is what renders.
  #
  # THE SHAPE THIS EXAMPLE USED TO ASSERT WAS THE DEFECT. `#unbudgeted?` was `holding.nil?` and
  # `#holding` is the category whenever it counts this day's spending, so the card drew an envelope
  # reading `$0.00 → −$55.00 left` in danger red with "This envelope goes over" underneath — an
  # envelope going over that nothing had ever claimed — while Home's "This period" printed the same
  # category as `spent $X` with no bar. `Category#budgeted?` is the one predicate both ask now.
  describe "a category that is funded but carries no rule" do
    before do
      create(:category, :expense, user: user, name: "Gifts", funded_since: funded_since)

      visit new_entry_path
    end

    it "gets the honest card rather than an envelope claiming nothing", :aggregate_failures do
      select_category("Gifts")

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(figure("headline")).to have_text("Nothing claims this yet")
      expect(page).to have_no_css("[data-figure='balance']", visible: :all)
      expect(page).to have_no_css("[data-figure='bar']", visible: :all)
    end

    # AND IT STAYS THE HONEST CARD WITH A FIGURE TYPED, which is the half that was painted red: no
    # overdraw line, because there is no envelope to go over.
    it "cannot be overdrawn however much is typed", :aggregate_failures do
      select_category("Gifts")
      fill_in "Amount", with: "55"

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(page).to have_no_css("[data-figure='buffer']", visible: :all)
      expect(page).to have_button("Create Entry")
      expect(page).to have_no_button("Save anyway")
    end

    # THE OTHER DIRECTION, ON THE SAME SCREEN: give a category one rule and it is an envelope with a
    # figure and a bar. The pair is what makes this a pin on the RULE rather than on the copy.
    it "unlike a category with a rule, which gets the envelope, the figure and the bar", :aggregate_failures do
      select_category("Groceries")

      expect(page).to have_css("[data-impact-card='envelope']")
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

  # ** THE FUND ARM, KEYED ON THE RULE'S SHAPE (two-shapes spec §2). ** It asked `Category#savings?`
  # — a holder, with a target, carrying NO refill rule — then a figure on the CATEGORY, then the rule
  # whose unspent money carried over. It asks `ClaimCalculator#dated?` now, of the calculators the
  # card already builds, so the noun and the bar come from the same objects the figures do.
  #
  # "GOAL" IS RETIRED WITH THE NOUN. A goal was a kind of category; "fund" is what an accruing rule
  # does with money — it saves it toward a day — and a bill's fund and a savings goal are ONE shape.
  describe "a fund" do
    before do
      vacation = create(:category, :expense, user: user, name: "Vacation", funded_since: funded_since)
      # $600 OF A $2,400 TARGET, planted as §3.2 builds it: a $2,400 goal FOUR fortnights out on this
      # file's biweekly grid, so the boundaries left are four and one walked period accrues
      # `2,400 ÷ 4` = $600 — the figures a $600-a-period rule capped at $2,400 produced before the
      # shape was retired.
      create(
        :budget,
        category: vacation,
        amount: 2_400,
        basis: :monthly,
        interval_months: nil,
        anchor_date: Date.current + 55.days
      )

      visit new_entry_path
      select_category("Vacation")
    end

    it "takes the fund shape and subtracts what is spent", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='fund']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("envelope")).to have_text("Vacation fund")
        expect(figure("balance")).to have_text("$600.00")
        expect(figure("balance-after")).to have_text("$450.00")
        expect(figure("target")).to have_text("of $2,400.00")
      end
    end

    # THE ATTRIBUTE THE BROWSER USED TO MULTIPLY BY IS GONE. It carried +1 for a savings category,
    # and with one direction left it would be the constant -1 on every render.
    it "sends the browser no direction to decide", :aggregate_failures do
      expect(page).to have_no_css("[data-direction]")
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }
    end

    it "measures the bar against the rule's target", :aggregate_failures do
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }

      # 450 of 2,400.
      expect(page).to have_css("[data-figure='bar'][style*='width: 19%']")
      expect(page).not_to have_css("[data-figure='bar'][style*='width: 100%']")
    end

    # THE OTHER DIRECTION ON THE SURVIVING ARM: a fund CAN go negative, and it says so in the app's
    # ordinary overdraw vocabulary rather than being exempted from it.
    it "reads as the fund going negative when it is emptied", :aggregate_failures do
      fill_in "Amount", with: "5000"

      within(card) { expect(figure("balance-after")).to have_text("-$4,400.00") }
      expect(page).to have_button("Save anyway")
    end
  end

  # ** THE "fund that names no figure" DESCRIBE IS DELETED WITH THE SHAPE (two-shapes spec §7). **
  # It planted an uncapped fund — a rule that carried its money over toward no ceiling — and pinned
  # that the card kept the fund NOUN while the trailing phrase dropped its "of": there was nothing
  # for a fraction to be of. Every accruing rule names a figure now, so the state is unreachable; the
  # surviving way for this card to withhold a ceiling is a fund with a sibling rule, below.

  # ** A FUND WITH A SIBLING RULE PRINTS NO CEILING, AT THE BROWSER (fix round 1 — MED-4). ** This is
  # the premise the rewrite of "a goal whose rule carries a due date" lost: that describe planted a
  # category with a $2,400 figure of its own and a dated rule, and pinned that the CHROME did not
  # inherit the rule's shape. The shape and the figure are one record's now, so the question it was
  # really asking has moved — what happens when a category carries a fund AND something else?
  #
  # THE ANSWER IS THAT THE FIGURE STAYS THE CATEGORY'S AND THE CEILING GOES. `#balance` is Σ over
  # every rule on the category (§3.1's lane ruling forbids this card resolving which rule an entry
  # drains), so the fund's target is not a ceiling on it, and `$1,200.00 of $2,400.00` would read
  # half full over a fund that is a quarter full.
  #
  # PLANTED, both rules written now so each walks exactly ONE period (a rule accrues from the later
  # of its category's funding date and its own birthday, and this category was funded a year back):
  # the item-less goal plans `2,400 ÷ 4` = **$600.00**, and the $600 bill due three days out
  # is inside this period so `periods_left` is 1 and the catch-up asks the whole **$600.00**.
  # Σ **$1,200.00**; $150 typed leaves **$1,050.00**.
  describe "a fund with a bill beside it" do
    before do
      car = create(:category, :expense, user: user, name: "Car", funded_since: funded_since)
      create(
        :budget,
        category: car,
        amount: 2_400,
        basis: :monthly,
        interval_months: nil,
        anchor_date: Date.current + 55.days
      )
      create(
        :budget,
        category: car,
        item: create(:item, category: car, name: "Insurance"),
        amount: 600,
        interval_months: 1,
        anchor_date: Date.current + 3.days
      )

      visit new_entry_path
      select_category("Car")
    end

    it "keeps the fund shape and drops the ceiling", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='fund']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("envelope")).to have_text("Car fund")
        expect(figure("balance")).to have_text("$1,200.00")
        expect(figure("balance-after")).to have_text("$1,050.00")
        expect(figure("target")).to have_text("built up")
        expect(page).to have_no_content("of $2,400.00")
      end
    end
  end

  # ** A DATED BILL IS A FUND ON THIS CARD NOW, AND THAT IS §2's WIDENING (two-shapes spec §2). **
  # The example asserted "envelope" and "left": the classifier was the rule whose unspent money
  # carried over, and a dated bill was not one — so the card called money that was demonstrably being
  # SAVED UP toward a day an envelope, and said what was "left" of it. A bill's fund and a savings
  # goal are one shape, so the noun follows the walk: this money is built up toward $600 on a day.
  #
  # ** THE CATEGORY-LEVEL SCREENS STILL SAY ENVELOPE HERE, and the difference is deliberate. ** The
  # index card, the holdings card and the dashboard's band require an ITEM-LESS ONE-OFF (§3.1's lane
  # partition and "a bill is not a thing being saved toward"); this card is about what a RECEIPT does
  # to the money, and a receipt on this lane lands on a rule that accrues toward a date.
  #
  # PLANTED: a $600 bill due three days out, INSIDE the period anchored on today, so `periods_left`
  # is 1 and the catch-up formula asks the whole $600 now — `min(0 + 600, 600)` built up in one
  # walked period. $150 typed leaves **$450.00**.
  describe "a category whose only rule is a dated bill" do
    before do
      house = create(:category, :expense, user: user, name: "House Deposit", funded_since: funded_since)
      create(:budget, category: house, amount: 600, interval_months: 1, anchor_date: Date.current + 3.days)

      visit new_entry_path
      select_category("House Deposit")
    end

    it "takes the fund shape and measures against the bill", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='fund']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("envelope")).to have_text("House Deposit fund")
        expect(figure("balance-after")).to have_text("$450.00")
        expect(figure("target")).to have_text("of $600.00")
        expect(page).to have_no_content("left")
      end
    end
  end

  describe "editing an entry the ledger has already counted" do
    let!(:existing) do
      create(:entry, item: weekly_shop, amount: 45, date: Date.current)
    end

    before { visit edit_entry_path(existing) }

    # The claim is $195 — a $300 rate less the fixture's $60 and this $45. The card says $240,
    # because the question on the screen is what this entry costs, not what the last one did.
    it "opens on the world without this entry, then puts it back", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='envelope']")

      expect(groceries.claim).to eq(BigDecimal("195"))
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
      create(:budget, :per_period_rate, category: dining, amount: 100)
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
      create(:entry, item: weekly_shop, amount: 300, date: Date.current)
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
