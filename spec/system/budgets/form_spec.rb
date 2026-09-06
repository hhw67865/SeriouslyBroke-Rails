# frozen_string_literal: true

require "rails_helper"

# THE RULE FORM, ONE CATEGORY (two-shapes spec §5) AND EVERY SHAPE (rules-own-the-budget spec §4).
#
# WHAT THIS FILE USED TO BE, FOUR TIMES OVER. Every example was once about the monthly category CAP
# — a form reached as `/budgets/new?category_id=…`, a "Set spending limits for Groceries" heading, a
# "Prorate daily" checkbox — and all of it was deleted with the cap in plan 3. What replaced it was
# a POOL-mode rule form; that went with the pool layer. Then came the hand-made rule form with an
# owner PICKER, which could write every row of the shape table but had to ask which category it was
# for. It does not ask any more: §5 makes the form its own PAGE, opened from the category it is
# about, titled by it, with that category's items in its select and that category's suggestions as
# chips above step 1 — so `?category_id=` is back in the URL, meaning the opposite of what it meant
# in the cap era (the OWNER of the rule, not a category being capped).
#
# ONE BROWSER PASS PER SHAPE, and each asserts the COLUMNS rather than a flash: a form that posts
# the right words to a mapping that has quietly changed still says "successfully created".
RSpec.describe "Budgets Forms", type: :system do
  let(:user) { create(:user, :biweekly, typical_income: 2_400) }
  let!(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  before { sign_in user, scope: :user }

  # ---------------------------------------------------------------------------------------------
  # §2.1's rows, written by hand
  # ---------------------------------------------------------------------------------------------
  describe "writing every shape by hand", :aggregate_failures do
    before do
      visit new_budget_path(category_id: groceries.id)
      choose "Usage"
    end

    # §2.1 row 1. THE FORM OPENS ON THIS SHAPE, so the only control it needs is the amount — which
    # is exactly what a hand-made rule meant before this task, and is now the default rather than
    # the ceiling.
    it "writes a per-period rate that resets" do
      fill_in "Amount", with: "400"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      rule = groceries.budgets.sole
      expect(rule).to have_attributes(basis: "per_period", interval_months: nil, anchor_date: nil, amount: 400)
    end

    # ** ROWS 2, 3 AND 4 WERE DELETED WITH THE SHAPE THEY WROTE (two-shapes spec §2/§7), AND ONE OF
    # THEM IS BACK (§12). ** They were the uncapped fund ("a number saved per period … that you could
    # allow to infinitely grow"), the goal that built toward a target, and the goal fed by hand at a
    # $0 rate — all three written by choosing "Builds up" and filling (or leaving blank) a Target.
    # The Target and the radio pair stay deleted: a goal IS a dated rule whose amount is its target,
    # written "$5,000 by Jun 1, 2027". What §12 restores is the FIRST of the three, as one checkbox
    # under "Every period" — an allowance that grows with no limit and no day.
    #
    # ** THE CHECKBOX IS THE WHOLE CONTROL, AND THE COLUMNS ARE WHAT IS ASSERTED. ** "Keeps what it
    # doesn't spend" beside a $510 amount is `per_period, no interval, no anchor, keeps_unspent` —
    # the rate rule's own three columns plus the one that says the boundary leaves the money alone.
    it "writes a fund that keeps what it doesn't spend" do
      fill_in "Amount", with: "510"
      check "Keeps what it doesn't spend"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      rule = groceries.budgets.sole
      expect(rule).to have_attributes(
        basis: "per_period", interval_months: nil, anchor_date: nil, amount: 510, keeps_unspent: true
      )
    end

    # THE OTHER DIRECTION, one click apart: the same form with the box left alone writes an
    # allowance that resets, so the example above cannot be passing on a default.
    it "leaves the box alone and writes an allowance that resets" do
      fill_in "Amount", with: "510"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole.keeps_unspent).to be(false)
    end

    # ** "Every month" IS NOT ON THE FORM ANY MORE (two-shapes §5's ruling). ** `monthly` with no due
    # date is a legal row and `SuggestionEngine` still writes one; it is not a shape people write by
    # hand, so the two options cover what they do write and `RuleForm.from` reads an existing one back
    # as "Every period". The example that wrote it by hand goes with the option.

    # §2 row 4 — the half-yearly bill, which could only ever arrive MEASURED from the suggestion panel
    # before this form. The checkbox is what adds the interval.
    it "writes a bill that repeats every N months from a date" do
      fill_in "Amount", with: "600"
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      check "Repeats every N months"
      fill_in "Comes round every (months)", with: "6"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to have_attributes(
        basis: "monthly", interval_months: 6, anchor_date: Date.new(2026, 12, 1)
      )
    end

    # §2 row 3. A NULL interval beside a date is the whole of "one-time", and the box is UNTICKED by
    # default so a repeating rule is the deliberate choice.
    it "writes a one-time bill on a date" do
      fill_in "Amount", with: "600"
      choose "By a date"

      expect(page).to have_no_field("Comes round every (months)")

      fill_in "Due", with: Date.new(2026, 12, 1)
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to have_attributes(
        basis: "monthly", interval_months: nil, anchor_date: Date.new(2026, 12, 1)
      )
    end

    # ** §2 ROW 5 — A GOAL, AND IT IS ROW 3 WITH A LONGER HORIZON. ** This is the whole of what §2
    # changed for this form: "$5,000 by Jun 1, 2027" writes the same three columns a bill does, so
    # there is no second question to ask about what becomes of the money.
    it "writes a goal as a one-off with a distant date" do
      fill_in "Amount", with: "5000"
      choose "By a date"
      fill_in "Due", with: Date.new(2027, 6, 1)
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to have_attributes(
        amount: 5_000, basis: "monthly", interval_months: nil, anchor_date: Date.new(2027, 6, 1)
      )
    end

    it "writes the type the user chose" do
      choose "Choice"
      fill_in "Amount", with: "75"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to be_choice
    end

    # ** "lands one on a savings category too" IS THIS EXAMPLE, THROUGH THE DOOR THAT REPLACED THE
    # PICKER. ** It used to `select "Vacation to Europe", from: "Category"`; there is no select, so
    # what it now pins is that the category in the URL is the category the rule lands on — which is
    # the whole promise "+ New rule for Vacation to Europe" makes.
    it "lands the rule on the category the door named" do
      vacation = create(:category, :expense, :funded, user: user, name: "Vacation to Europe")

      visit new_budget_path(category_id: vacation.id)
      choose "Usage"
      fill_in "Amount", with: "60"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(vacation.budgets.sole.amount).to eq(60)
      expect(groceries.budgets).to be_empty
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The page §5 describes: three numbered steps, a preview beside them
  # ---------------------------------------------------------------------------------------------
  describe "the page", :aggregate_failures do
    before { visit new_budget_path(category_id: groceries.id) }

    it "is titled and breadcrumbed by the category it was opened from" do
      expect(page).to have_content("New rule for Groceries")
      expect(page).to have_content("Change any blank. Nothing is saved until you press the button.")
      expect(page).to have_link("Budget", href: budget_page_path)
      expect(page).to have_no_select("Category")
    end

    it "asks the three questions in order" do
      expect(page).to have_content("1. What is this rule for, and how much?")
      expect(page).to have_content("2. When is it needed?")
      expect(page).to have_content("3. What kind of rule is this?")
    end

    # ** THE SELECT IS THIS CATEGORY'S ITEMS AND NOTHING ELSE (§5). ** It used to be every item the
    # user owns, filtered in the browser as the owner picker moved; with one category in force there
    # is nothing to filter between, so the assertion is on the whole option list rather than on what
    # is selectable. "The whole category" is the blank, first, and its MEANING is on the page —
    # "anything in Groceries no other rule pays" — because a lane nobody named is the one thing a
    # user cannot infer from a select.
    it "offers this category's items, the whole category first, and says what that means" do
      create(:item, category: groceries, name: "Milk")
      utilities = create(:category, :expense, :funded, user: user, name: "Utilities")
      create(:item, category: utilities, name: "Power")

      visit new_budget_path(category_id: groceries.id)

      expect(page).to have_select("Pays", options: ["the whole category", "Milk"])
      expect(page).to have_content("means anything in Groceries no other rule pays")
    end

    it "lands the rule on the item it says it pays" do
      milk = create(:item, category: groceries, name: "Milk")

      visit new_budget_path(category_id: groceries.id)
      select "Milk", from: "Pays"
      choose "Bill"
      fill_in "Amount", with: "90"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole.item).to eq(milk)
    end

    # ** THE PREVIEW SAYS THE RULE BACK, AND IT IS THE SERVER'S (§5). ** Rendered on first load with
    # the blanks it is missing, then re-rendered into its Turbo Frame as they are filled — every
    # figure off ONE `ClaimCalculator`, which is why the per-period figure here and the Budget page's
    # tiles cannot disagree.
    # §12'S OWN FORM STATE, filled once for the two examples that read the card it produces.
    def describe_a_fund
      choose "Usage"
      fill_in "Amount", with: "510"
      check "Keeps what it doesn't spend"
    end

    # ** A MUTATION OBSERVER, INSTALLED BEFORE THE CHANGE (§12). ** The highlight class is added on
    # `turbo:frame-load` and removed 600ms later, so polling for it is a race; this records that it
    # happened onto the document, where an ordinary Capybara matcher can wait for it.
    def watch_for_the_highlight
      page.execute_script(<<~JS)
        const frame = document.querySelector("turbo-frame#rule_preview");
        new MutationObserver((records) => {
          records.forEach((record) => {
            if (record.target.classList && record.target.classList.contains("preview-refreshed")) {
              document.documentElement.setAttribute("data-saw-highlight", "1");
            }
          });
        }).observe(frame, { subtree: true, attributes: true, attributeFilter: ["class"] });
      JS
    end

    it "starts by naming the blanks it needs" do
      within("[data-preview]") do
        expect(page).to have_content("Fill in an amount.")
        expect(page).to have_content("Choose what kind of rule this is.")
      end
    end

    it "says a per-period rule back as the blanks are filled" do
      choose "Usage"
      fill_in "Amount", with: "400"

      within("[data-preview]") do
        expect(page).to have_content("Groceries gets $400.00 every period")
        expect(page).to have_content("It's usage, so it gives way after your choices and before your bills.")
        expect(page).to have_css("[data-preview-figure='per_period']", text: "$400.00")
      end
    end

    # THE OTHER SHAPE, AND THE ARITHMETIC UNDER IT: a dated rule's card names the periods it has to
    # fill in and prices itself over them, which is the figure a per-period allowance has no need of.
    it "prices a dated rule over the periods it has left" do
      choose "Bill"
      fill_in "Amount", with: "600"
      choose "By a date"
      fill_in "Due", with: Date.current + 6.months

      within("[data-preview]") do
        expect(page).to have_content("It's a bill, so it's the last thing to give way.")
        expect(page).to have_content("Each period sets aside its share so the money is there on the day.")
        expect(page).to have_css("[data-preview-figure='periods_left']")
      end
    end

    # AND IT KEEPS UP. The card is re-rendered by the server on every change (debounced), so a figure
    # that stopped following the box would be a card describing a rule the user has moved on from.
    it "follows the amount box" do
      choose "Usage"
      fill_in "Amount", with: "400"

      expect(page).to have_css("[data-preview-figure='per_period']", text: "$400.00")

      fill_in "Amount", with: "550"

      expect(page).to have_css("[data-preview-figure='per_period']", text: "$550.00")
    end

    # ** §12'S CARD: THE FUND SAID BACK. ** Three sentences and two figures, and what is NOT there is
    # as much of the assertion as what is: there is no "Periods until" row, because a rule that keeps
    # what it doesn't spend has no day to count toward.
    it "says a fund back in words", :aggregate_failures do
      describe_a_fund

      within("[data-preview]") do
        expect(page).to have_content("Groceries gets $510.00 every period and keeps what it doesn't spend")
        expect(page).to have_content("It builds up with no limit.")
      end
    end

    # AND THE ARITHMETIC UNDER THEM — with the "Periods until" row ABSENT, which is as much of the
    # assertion as the two figures that are there: a rule that keeps what it doesn't spend has no day
    # to count toward. The "Home will show" row is `HomeHelper`'s own words off the same calculator,
    # which is what makes the card's promise checkable against the Budget page a click away.
    it "prices a fund with no day to count to", :aggregate_failures do
      describe_a_fund

      within("[data-preview]") do
        expect(page).to have_css("[data-preview-figure='per_period']", text: "$510.00")
        expect(page).to have_css("[data-preview-figure='built_up']", text: "$510.00")
        expect(page).to have_no_css("[data-preview-figure='periods_left']")
        expect(page).to have_css("[data-preview-figure='home']", text: "built up $510.00")
        expect(page).to have_css("[data-preview-figure='home']", text: "+$510.00 a period")
      end
    end

    # ** THE PREVIEW BUTTON IS DELETED (§12). ** It was a visible secondary control beside Cancel and
    # it was the no-JavaScript path; §12 rules that there is no preview without JavaScript, so the
    # button has nothing left to be for. The SUBMITTER survives hidden — a hidden button is still a
    # valid `requestSubmit` submitter — which is what carries the `formaction` the refreshes above go
    # through, and `have_no_button` is exactly the right assertion for it: it asks about what a user
    # can see and press.
    it "offers no Preview button, and refreshes without one", :aggregate_failures do
      expect(page).to have_no_button("Preview")
      expect(page).to have_button("Create rule")

      choose "Usage"
      fill_in "Amount", with: "400"

      expect(page).to have_css("[data-preview-figure='per_period']", text: "$400.00")
    end

    # ** THE CARD IS REVEALED BY STIMULUS, WHICH IS WHY IT IS THERE AT ALL (§12). ** The server
    # renders the frame `hidden`; `connect()` lifts it. A browser is the only place that half can be
    # asserted — the request spec pins the other half, that a non-Turbo response leaves it hidden.
    it "reveals the card that the server rendered hidden", :aggregate_failures do
      expect(page).to have_css("turbo-frame#rule_preview", visible: :visible)
      expect(page).to have_css("[data-preview]", visible: :visible)
    end

    # ** EVERY REFRESH BRIEFLY HIGHLIGHTS THE CARD (§12). ** The card sits in the second column,
    # inches from the box, and a figure that changes with no other signal is a change nobody looks
    # for. The class is added on `turbo:frame-load` and removed 600ms later, so it cannot be caught
    # by polling reliably — a MutationObserver installed BEFORE the change records that it happened,
    # and the assertion is an ordinary Capybara one against the flag it leaves on the document.
    #
    # THE OBSERVER IS INSTALLED FIRST AND THE LAST STATEMENT IS A CAPYBARA WAIT, which is CLAUDE.md's
    # rule about JavaScript in this suite: it is a trailing `evaluate_script` that leaves the session
    # in a state teardown does not survive.
    it "highlights the card each time it is refreshed" do
      watch_for_the_highlight

      choose "Usage"
      fill_in "Amount", with: "400"

      expect(page).to have_css("[data-preview-figure='per_period']", text: "$400.00")
      expect(page).to have_css("html[data-saw-highlight='1']", visible: :all)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # What each choice reveals, and what it hides
  # ---------------------------------------------------------------------------------------------
  describe "the reveals", :aggregate_failures do
    before { visit new_budget_path(category_id: groceries.id) }

    # THE FORM OPENS ON "Every period", so all three dated controls are away. A blank date input on a
    # per-period form is an invitation to write a shape the model refuses.
    it "opens with the dated fields away" do
      expect(page).to have_no_field("Due")
      expect(page).to have_no_field("Repeats every N months")
      expect(page).to have_no_field("Comes round every (months)")
    end

    # ** "By a date" REVEALS THE DATE AND THE CHECKBOX, AND THE CHECKBOX REVEALS THE INTERVAL. **
    # Two steps rather than one, because "every 6 months" is a detail OF "by a date" and not a
    # different answer to when the money is needed.
    it "reveals the date and the repeats box, and the interval only when it is ticked", :aggregate_failures do
      choose "By a date"

      expect(page).to have_field("Due")
      expect(page).to have_field("Repeats every N months")
      expect(page).to have_no_field("Comes round every (months)")

      check "Repeats every N months"

      expect(page).to have_field("Comes round every (months)")
    end

    # ** THE "Unspent money" EXAMPLES WERE DELETED WITH THE STEP (two-shapes §5/§7) AND ONE
    # CHECKBOX TOOK THEIR PLACE (§12). ** Four of them pinned that the radios and the Target were on
    # screen for a dateless schedule, hidden AND DISABLED for a dated one, live again on the way
    # back, and that the Target appeared only under "Builds up". The Target is gone for good — a goal
    # IS a dated rule — and what is left of the question is "Keeps what it doesn't spend", which is
    # NOT hidden under "By a date" but DISABLED and cleared: hiding it would take the one control
    # that says what happens to unspent money off the screen where the answer is most surprising.
    # ** THE HINT SAYS THE SHAPE WITHOUT THE RETIRED NOUN (fix round — LOW). ** §7 took "fund" off
    # every screen and §10.6 recorded what survived — an informal "a bill or a goal" in the option
    # help, and "Fund account" on the onboarding card, which is a verb about a bank account. The
    # checkbox's own hint must not put the noun back.
    it "explains the box in the app's own words, without the retired noun", :aggregate_failures do
      expect(page).to have_content("an allowance that keeps building")
      expect(page).to have_content("whatever you don't spend stays claimed, with no limit")
      expect(find("[data-step='2']")).to have_no_content("fund")
    end

    it "keeps the keeps box on screen and disables it under By a date", :aggregate_failures do
      expect(page).to have_field("Keeps what it doesn't spend", disabled: false)

      choose "By a date"

      expect(page).to have_field("Keeps what it doesn't spend", disabled: true)

      choose "Every period"

      expect(page).to have_field("Keeps what it doesn't spend", disabled: false)
    end

    # ** AND THE TICK IS CLEARED ON THE WAY PAST, NOT STASHED. ** A hidden or disabled box still
    # describes an answer, and `Budget#keeps_unspent_never_dates` refuses a dated rule that keeps —
    # so a box left ticked would be a 422 about a control the user cannot reach. Nothing is put back
    # when the schedule returns, unlike the date field: the box is a two-state answer to a question
    # this schedule does not ask, and restoring it would re-tick a box the user last saw empty.
    it "clears the keeps box when the schedule moves to a date and does not put it back", :aggregate_failures do
      check "Keeps what it doesn't spend"
      choose "By a date"

      expect(page).to have_field("Keeps what it doesn't spend", checked: false, disabled: true)

      choose "Every period"

      expect(page).to have_field("Keeps what it doesn't spend", checked: false, disabled: false)
    end

    # AND THE SAVE AGREES WITH THE SCREEN: a fund switched to "By a date" writes a dated rule with
    # the keeping off, rather than the pair the model refuses.
    it "writes a dated rule with no keeping when the user changes their mind" do
      check "Keeps what it doesn't spend"
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      choose "Bill"
      fill_in "Amount", with: "600"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole)
        .to have_attributes(anchor_date: Date.new(2026, 12, 1), keeps_unspent: false)
    end

    it "takes the interval away again when the box is unticked" do
      choose "By a date"
      check "Repeats every N months"
      uncheck "Repeats every N months"

      expect(page).to have_no_field("Comes round every (months)")
    end

    # ** A HIDDEN FIELD STILL SUBMITS, SO THE CONTROLLER CLEARS IT. ** A user who typed a due date
    # and then chose "per period" would otherwise send a date the form no longer shows, and
    # `RuleForm` refuses a due date on a per-period rule rather than laundering it away — the
    # refusal would be about a control that is not on screen. Asserted through the SAVE, because
    # that is the only place the leftover value could do harm.
    it "forgets a date the user typed and then chose away from" do
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      choose "Every period"
      choose "Usage"
      fill_in "Amount", with: "400"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to have_attributes(basis: "per_period", anchor_date: nil)
    end

    # AND IT PUTS THE VALUE BACK, so a toggle back and forth does not cost the user their typing.
    it "puts a typed date back when the schedule returns to it" do
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      choose "Every period"
      choose "By a date"

      expect(page).to have_field("Due", with: "2026-12-01")
    end

    # ** THE ITEM FILTER IS DELETED WITH THE PICKER (§5), AND SO ARE ITS TWO EXAMPLES. ** They
    # pinned that "Pays" listed every item the user owns while hiding and disabling the ones outside
    # the chosen category, and that the list changed as the picker moved. There is no picker and no
    # cross-category list: the select IS the category's items, which "offers this category's items"
    # above asserts as a whole option list rather than as a filter's residue.
  end

  # ---------------------------------------------------------------------------------------------
  # The chips (§5)
  # ---------------------------------------------------------------------------------------------
  #
  # ** THE ENGINE HAS ALREADY MEASURED THE RULE THE USER CAME HERE TO WRITE. ** A chip is that
  # measurement offered as a fill: the same sentence the Budget page's panel prints, with a button
  # that puts every figure in the blanks. The history is PLANTED rather than stubbed, for
  # `suggestions_spec`'s own reason — a stubbed engine would pin this page against a fixture instead
  # of against the app.
  describe "the suggestion chips", :aggregate_failures do
    let!(:phone) { create(:item, category: groceries, name: "Phone") }

    before do
      plant_bill(phone, 85)
      visit new_budget_path(category_id: groceries.id)
    end

    it "offers the category's own suggestions above the first step" do
      within("[data-chips]") do
        expect(page).to have_content("Phone — $85.00 every month")
        expect(page).to have_button("Use this")
      end
    end

    # ** ONE CLICK FILLS EVERY BLANK IT HAS A MEASUREMENT FOR. ** Not some of them: the amount, the
    # lane, the type, the schedule, the interval and the date are one proposal, and a chip that
    # filled four of the six would leave the user to guess which two it had opinions about.
    # ** THE AMOUNT ARRIVES AS MONEY (fix wave — Task 5's minor). ** The prefill carried
    # `BigDecimal#to_s`, so a click filled the box with `85.0` — and a measured $122.14 with `122.0`
    # beside a chip whose own sentence said `$122.00`. `%.2f` in the chip's data is what the box's
    # `step: 0.01` is for. "✓ Using this" is unaffected: `fieldMatches` compares money as a NUMBER
    # precisely so a reformat cannot unset a chip, which is what keeps the query-string door below
    # (still server-rendered as `85.0`) reading as applied.
    it "fills every blank from one click" do
      click_button "Use this"

      expect(page).to have_field("Amount", with: "85.00")
      expect(page).to have_select("Pays", selected: "Phone")
      expect(page).to have_checked_field("Bill")
      expect(page).to have_checked_field("By a date")
      expect(page).to have_checked_field("Repeats every N months")
      expect(page).to have_field("Comes round every (months)", with: "1")
      expect(page).to have_field("Due", with: expected_due_on.strftime("%Y-%m-%d"))
    end

    # ** "✓ Using this" IS A READING OF THE BLANKS, NOT A MEMORY OF THE CLICK (§5). ** A user who
    # accepts a chip and then edits the amount has stopped using it, and a chip that went on claiming
    # otherwise would be the page asserting something the fields on it contradict.
    it "says it is being used while the blanks still match, and stops when they do not" do
      click_button "Use this"

      expect(page).to have_button("✓ Using this")

      fill_in "Amount", with: "90"

      expect(page).to have_button("Use this")
    end

    # THE PREVIEW FOLLOWS THE CHIP, which is what makes the pair one act: the chip says what the
    # engine measured and the card says what that rule would DO.
    it "brings the preview with it" do
      click_button "Use this"

      within("[data-preview]") do
        expect(page).to have_content("Phone gets $85.00 every month")
      end
    end

    # ** A "Write it →" ARRIVAL LANDS WITH THE CHIP ALREADY APPLIED (§5). ** The link carries the
    # payload in the query string, the server renders the form holding it, and the chip's own state
    # is computed from those blanks — so the two doors into this form (fill it here, or arrive
    # filled) end in the same place with the same thing said about it.
    it "arrives already applied when the Budget page wrote it into the URL" do
      visit budget_page_path
      find("[data-category-row='Groceries'] a[href*='open=']", match: :first).click
      within("[data-suggestions='Groceries']") { click_link "Write it →" }

      expect(page).to have_field("Amount", with: "85.0")
      expect(page).to have_button("✓ Using this")
    end

    # TWO PAYMENTS A WHOLE MONTH APART, THE SAME SIZE: the measured dated-bill shape, exactly as
    # `suggestions_spec` plants it.
    def plant_bill(item, amount)
      create(:entry, item: item, amount: amount, date: Date.current - 2.months)
      create(:entry, item: item, amount: amount, date: Date.current - 1.month)
    end

    def expected_due_on = (Date.current - 1.month) >> 1
  end

  # ---------------------------------------------------------------------------------------------
  # The refusals a user can actually meet
  # ---------------------------------------------------------------------------------------------
  describe "refusals", :aggregate_failures do
    before { visit new_budget_path(category_id: groceries.id) }

    # ** THE OWNER-LESS SAVE LEFT THIS FILE WITH THE PICKER (§5). ** It pinned that a form submitted
    # with no category chosen came back with `must belong to a category` on `:base` and the select
    # still on screen. There is no select and no way to reach that state from a browser — the form
    # carries the category it was opened on in a hidden field — so what survives of it is the
    # request spec's own `answers a rule with no owner at all with a 422`, which is the shape a
    # hand-made POST can still make.

    # EVERY RULE HAS A TYPE (§3) and the give-way order is built on it, so no radio is preselected
    # on a hand-made rule and the save is refused until one is.
    it "refuses a rule with no type chosen" do
      fill_in "Amount", with: "400"
      click_button "Create rule"

      expect(page).to have_content("Type can't be blank")
      expect(Budget.count).to eq(0)
    end

    it "refuses a missing amount" do
      choose "Usage"
      click_button "Create rule"

      expect(page).to have_content("can't be blank")
      expect(Budget.count).to eq(0)
    end

    # THE SHAPE ERRORS LAND UNDER "WHEN IS IT NEEDED?", which is the question they are details of —
    # `Budget` states them on `interval_months`, a column this form does not render.
    it "refuses a repeating rule with no number of months, under When it is needed" do
      choose "Usage"
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      check "Repeats every N months"
      fill_in "Amount", with: "600"
      click_button "Create rule"

      expect(page).to have_content("When it is needed needs the number of months")
      expect(Budget.count).to eq(0)
    end

    it "refuses a dated rule with no date, under When it is needed" do
      choose "Usage"
      choose "By a date"
      fill_in "Amount", with: "600"
      click_button "Create rule"

      expect(page).to have_content("When it is needed needs the date it is first due")
      expect(Budget.count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # Editing — every control but the category
  # ---------------------------------------------------------------------------------------------
  describe "Edit rule form", :aggregate_failures do
    let!(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400.00, rule_type: :usage) }

    before { visit edit_budget_path(rule) }

    it "shows the rule's own controls and none of the cap's" do
      expect(page).to have_content("Groceries — edit rule")
      expect(page).to have_field("Amount")
      expect(page).to have_button("Update rule")
      expect(page).to have_link("Cancel")

      expect(page).to have_no_field("Prorate daily")
      expect(page).to have_no_select("Pool")
    end

    # ** §4: "EDIT EXPOSES EVERYTHING BUT THE CATEGORY." ** The form that refused to re-offer a
    # rule's shape is deleted, and with it the hint that said so ("the schedule itself is already
    # set on this rule"). The category stays read-only because the page that LISTS rules groups them
    # by category, so moving one between categories is that list's act rather than a control buried
    # in one rule's form.
    # ** IT SUBMITS NOTHING FOR THE CATEGORY EITHER (fix round 1 — M1). ** The read-only box used to
    # sit over a hidden field, and the field's only real effect was to make a re-parent a legal
    # PATCH that no control here could ask for. `#update` does not permit the key any more, so the
    # form does not carry it; the rule keeps its owner because the ROW has one, and the category is
    # said by the breadcrumb instead.
    it "exposes every control but the category" do
      expect(page).to have_no_select("Category")
      expect(page).to have_content("Groceries")
      expect(page).to have_no_css("input[name='budget[category_id]']", visible: :all)

      expect(page).to have_select("Pays")
      expect(page).to have_field("Bill")
      expect(page).to have_field("Every period")
      expect(page).to have_field("By a date")
      expect(page).to have_no_content("Unspent money")
      expect(page).to have_no_content("the schedule itself is already set")
    end

    it "pre-fills the amount and the choices the rule was written with", :aggregate_failures do
      expect(page).to have_field("Amount", with: "400.0")
      expect(page).to have_checked_field("Every period")
      expect(page).to have_checked_field("Usage")
    end

    # THE DESTINATION IS THE BUDGET PAGE, which is the screen the Edit link was clicked from and
    # the only screen that lists rules.
    it "updates the rule and returns to the Budget page" do
      fill_in "Amount", with: "750.00"
      click_button "Update rule"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Budget was successfully updated")
      expect(rule.reload.amount).to eq(750.00)
    end

    # ** A SHAPE CHANGE ON AN EXISTING RULE IS LEGAL (§5). ** The claim is computed, so the walk
    # re-runs from the rule's accrual start under the new shape — nothing is migrated and nothing is
    # stale, which is the whole reason the edit form may now offer the schedule at all.
    #
    # ** "turns a rate rule into a fund with a target" IS THIS EXAMPLE NOW (two-shapes §2). ** It
    # chose "Builds up" and typed a Target; a fund IS a dated rule whose amount is its target, so an
    # allowance becomes a goal by naming the day the money is needed.
    it "turns an allowance into a goal" do
      fill_in "Amount", with: "5000"
      choose "By a date"
      fill_in "Due", with: Date.new(2027, 6, 1)
      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(rule.reload).to have_attributes(
        amount: 5_000, basis: "monthly", interval_months: nil, anchor_date: Date.new(2027, 6, 1)
      )
      expect(rule.claim_shape).to eq(:dated)
    end

    it "turns a rate rule into a repeating dated bill" do
      choose "By a date"
      fill_in "Due", with: Date.new(2026, 12, 1)
      check "Repeats every N months"
      fill_in "Comes round every (months)", with: "6"
      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(rule.reload).to have_attributes(interval_months: 6, anchor_date: Date.new(2026, 12, 1))
      expect(rule.claim_shape).to eq(:dated)
    end

    it "shows an error for a missing amount" do
      fill_in "Amount", with: ""
      click_button "Update rule"

      expect(page).to have_current_path(edit_budget_path(rule))
      expect(page).to have_content("can't be blank")
      expect(rule.reload.amount).to eq(400.00)
    end

    it "returns to the Budget page when clicking cancel" do
      click_link "Cancel"

      expect(page).to have_current_path(budget_page_path)
    end
  end

  # THE DATED RULE'S OWN EDIT FORM, which is where a wrong reverse mapping shows up: a rule opened
  # and saved with nothing touched must come back the shape it went in as.
  describe "editing a dated bill", :aggregate_failures do
    let!(:bill) do
      create(
        :budget,
        :recurring,
        category: groceries,
        amount: 800,
        rule_type: :bill,
        interval_months: 6,
        anchor_date: Date.new(2026, 6, 1)
      )
    end

    before { visit edit_budget_path(bill) }

    it "opens on the schedule it was written with", :aggregate_failures do
      expect(page).to have_checked_field("By a date")
      expect(page).to have_checked_field("Repeats every N months")
      expect(page).to have_checked_field("Bill")
      expect(page).to have_field("Comes round every (months)", with: "6")
      expect(page).to have_field("Due", with: "2026-06-01")
      expect(page).to have_no_content("Unspent money")
    end

    it "keeps its shape through a save that changes nothing else" do
      fill_in "Amount", with: "900"
      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(bill.reload).to have_attributes(
        amount: 900, basis: "monthly", interval_months: 6, anchor_date: Date.new(2026, 6, 1)
      )
    end
  end

  # ** THE `monthly`-NO-ANCHOR ROW, WHICH THE FORM DOES NOT OFFER AND HAS TO OPEN ANYWAY
  # (two-shapes §5's ruling, corrected in fix round 1). ** `SuggestionEngine` still writes "$260 every
  # month", and `RuleForm.from` reads it back as "Every period" — at what the rule COSTS a period,
  # `Budget#steady_ask`'s $120.00 on this user's fortnightly grid. Saving it untouched writes
  # `per_period 120.00`, so the shape changes and the money does not.
  #
  # THE PAGE SAYS IT TWICE, IN TWO REGISTERS: the note under the amount explains why the box is not
  # the figure the user remembers typing, and the PREVIEW states the two figures as money. That pair
  # is what closes this task's carry — a drift suggestion accepted on such a rule used to write 3.6×
  # the per-period figure it proposed, and now writes exactly it.
  describe "editing a monthly rule the form does not offer", :aggregate_failures do
    let!(:monthly) { create(:budget, :rate, category: groceries, amount: 260, rule_type: :usage) }

    before { visit edit_budget_path(monthly) }

    it "opens as Every period, at what the rule costs a period, and says why" do
      expect(page).to have_checked_field("Every period")
      expect(page).to have_field("Amount", with: "120.0")
      expect(page).to have_content("What this rule asks for per period.")
      expect(find("[data-monthly-conversion]")).to have_content(
        "This rule was $260.00 a month — shown here as what it costs each period on your biweekly grid. " \
        "Saving keeps that cost."
      )
    end

    # ** AND IT SAYS IT ONCE (fix wave — MED-4/T4(a)). ** The "Currently $260.00 a month." line
    # renders wherever the box differs from the row's stored figure, which is TRUE of every converted
    # edit — so it stood under the note saying the same thing in fewer words. The note is the fuller
    # sentence and this shape is exactly the one it exists for, so the line stands down here.
    it "does not repeat the row's monthly figure in a second line" do
      expect(page).to have_no_css("[data-current-amount]")
    end

    # ** THE DRIFT-ACCEPT PATH, WHERE THE NOTE WAS FALSE (fix wave — MED-4). ** `#edit` merges the
    # suggestion's measured amount over the read-back, so the box holds $200.00 — and the sentence
    # above went on claiming the box was "what it costs each period" and that "Saving keeps that
    # cost", about a figure that is neither the row's nor the conversion's, on the one act whose
    # entire purpose is to CHANGE the cost. The note names the three figures instead.
    it "names the proposal and the row where a suggestion filled the box", :aggregate_failures do
      visit edit_budget_path(monthly, budget: { amount: "200.0" })

      expect(page).to have_field("Amount", with: "200.0")
      expect(find("[data-monthly-conversion]")).to have_content(
        "Your entries suggest $200.00 a period. This rule was $260.00 a month " \
        "($120.00 a period on your biweekly grid)."
      )
      expect(page).to have_no_content("Saving keeps that cost")
      expect(page).to have_no_css("[data-current-amount]")
    end

    it "states both units on the preview card" do
      expect(find("[data-preview-units]")).to have_content("$260.00 a month · $120.00 a period on your biweekly grid")
    end

    # ** AND SAVING IT UNTOUCHED KEEPS THE COST, WHICH IS THE WHOLE OF THE RULING. ** The columns
    # change — this is the conversion §5 rules legal — and `Budget#steady_ask` reads the same figure
    # on both sides of it, which is the only sense in which a shape change can be said to be safe.
    it "saves the cost it opened on" do
      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(monthly.reload).to have_attributes(basis: "per_period", amount: 120)
      expect(monthly.steady_ask(user)).to eq(120)
    end

    # THE OTHER DIRECTION, so neither the note nor the two-unit line is a fixture of every edit form:
    # an ordinary per-period rule says nothing about months at all.
    it "says nothing of the sort on a rule whose words match its columns" do
      visit edit_budget_path(create(:budget, :per_period_rate, category: groceries, amount: 400, item: create(:item, category: groceries)))

      expect(page).to have_content("What this rule asks for per period.")
      expect(page).to have_no_css("[data-monthly-conversion]")
      expect(page).to have_no_css("[data-preview-units]")
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The door, and the two dead eras' controls
  # ---------------------------------------------------------------------------------------------
  #
  # ** THE PICKER IS DELETED AND THE DOOR MOVED INSIDE THE CATEGORY (§4/§5). ** This block used to
  # be "New rule form with no owner": it clicked the Budget page's header button, asserted the
  # picker offered this user's expense categories and no income one, and wrote a rule by choosing
  # one. There is no header button and no picker. What those examples were really protecting —
  # that a rule lands on the category the user meant, and that neither dead era's control has come
  # back — is asserted here on the door that replaced them.
  describe "the door onto a new rule", :aggregate_failures do
    it "is inside the category's own panel, and carries it" do
      visit budget_page_path
      find("[data-category-row='Groceries'] a[href*='open=']", match: :first).click
      click_link "+ New rule for Groceries"

      expect(page).to have_current_path(new_budget_path(category_id: groceries.id))
      expect(page).to have_content("New rule for Groceries")
      expect(page).to have_no_select("Pool")
      expect(page).to have_no_field("Prorate daily")
    end

    # ** AND THE CATEGORY-LESS URL IS NOT A PAGE. ** `/budgets/new` with nothing named has no title,
    # no item select and no chips — everything on this form is about one category — so it answers
    # with the page the doors are on and a sentence saying so, rather than with the picker it used
    # to open.
    it "sends a category-less URL back to the Budget page" do
      visit new_budget_path

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content(BudgetsController::NEW_NEEDS_A_CATEGORY)
    end

    # A RULE'S OWNER IS AN EXPENSE CATEGORY, never an income one — income lands in available and is
    # allocated out of it (§2), so a rule on one would claim money that category never holds. The
    # picker used to be the affordance; the LIST is, since the Budget page's rows are expense
    # categories and an income one has no door at all.
    it "does not exist for an income category" do
      salary = create(:category, :income, user: user, name: "Salary")

      visit budget_page_path

      expect(page).to have_no_css("[data-category-row='Salary']")
      expect(salary.reload.budgets).to be_empty
    end
  end

  # ---------------------------------------------------------------------------------------------
  # A TRUE 375px LAYOUT VIEWPORT
  # ---------------------------------------------------------------------------------------------
  #
  # CDP IS THE ONLY WAY TO GET ONE. Chrome refuses to make a headless window narrower than 500px —
  # `resize_to(375, 667)` and `--window-size=375,667` alike report `width=500`, measured — so every
  # window-based spelling of this test is really a 500px test wearing a 375 label.
  # `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is what CSS media queries
  # read. The idiom, and the measurements behind it, are in `spec/system/home/money_spec.rb`.
  #
  # SELENIUM'S OWN GEOMETRY AND NO TRAILING `evaluate_script`: an example whose last statement runs
  # JS leaves the session in a state Capybara's teardown does not survive here.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # THE TWO COLUMNS ARE THE NEW RISK (§5: "two columns at ≥1024px, one below"). Below that the
    # preview has to sit UNDER the steps rather than beside them, and the radio rows — a control, a
    # title and a line of help on one line — are the shape that pushes a page sideways when it
    # cannot wrap.
    #
    # ** THE PREVIEW IS MEASURED AGAINST STEP 3 AND NOT AGAINST THE FORM (fix round). ** The form is
    # the grid now and the card is INSIDE it, so `preview.y > form.y` had become true of any layout
    # whatsoever — an assertion that cannot fail is not one.
    it "stacks the preview under the steps and fits inside a 375px viewport", :aggregate_failures do
      visit new_budget_path(category_id: groceries.id)

      expect(page).to have_content("2. When is it needed?")
      expect(page).to have_field("Amount")

      card = page.find("form[action=\"#{budgets_path}\"]").native.rect
      radio = page.find("label", text: "money saved up toward a day").native.rect
      last_step = page.find("[data-step='3']").native.rect
      preview = page.find("[data-preview]").native.rect

      expect(card.x + card.width).to be <= 375
      expect(radio.x + radio.width).to be <= card.x + card.width
      expect(preview.y).to be > (last_step.y + last_step.height) - 1
    end

    # ** THE PREVIEW COMES BEFORE THE BUTTON ON A PHONE (fix round, 2026-09-06). ** The card says the
    # rule back — in words and in arithmetic — and the whole point of saying it is that it is read
    # BEFORE the rule is written. At ≥1024px it is beside the form, so the order is never in
    # question; stacked, it was after "Create rule", which asked a phone to press the button and
    # then scroll down to find out what it had agreed to. The grid is on the form now and the card
    # is a grid child between the steps and the buttons.
    it "puts the preview above the button that commits to it", :aggregate_failures do
      visit new_budget_path(category_id: groceries.id)

      expect(page).to have_field("Amount")

      preview = page.find("[data-preview]").native.rect
      create = page.find("input[type=submit]").native.rect

      expect(create.y).to be > (preview.y + preview.height) - 1
      expect(create.x + create.width).to be <= 375
    end

    # ** THE SENTENCE BREAKS BETWEEN ITS CLAUSES, NOT INSIDE ONE (mobile pass, 2026-09-06). **
    # "Set aside $___ for [the whole category ▾]" is one wrapping row of five children, and at 375
    # it broke wherever the width ran out: `Set aside $[___] for` on line one and the select alone
    # on line two, measured — the preposition orphaned from the thing it points at. `for` and the
    # select are bound into one full-width span below `sm` now, so the only break available is the
    # one between the clauses.
    #
    # THE SELECT BEING WIDER THAN THE AMOUNT BOX IS WHAT SAYS IT TOOK THE LINE: a select that had
    # merely wrapped would still be at its own content width beside a hanging word.
    it "puts the sentence's select on its own line rather than orphaning the word before it", :aggregate_failures do
      visit new_budget_path(category_id: groceries.id)

      expect(page).to have_field("Amount")

      step = page.find("[data-step='1']").native.rect
      amount = page.find("#budget_amount").native.rect
      item = page.find("#budget_item_id").native.rect

      expect(item.y).to be > (amount.y + amount.height) - 1
      expect(item.width).to be > amount.width
      expect(item.x + item.width).to be <= step.x + step.width
    end

    # ** THE CHIP'S ONE CONTROL IS FULL WIDTH AT 375 (mobile pass, fix round). ** Under two
    # sentences of measurement an 88px button reads as a footnote to them rather than as the thing
    # that fills the form in — and it is the only control on the card. The two entries are what make
    # a chip that HAS a button: a dead-rule chip carries no figure to fill a blank with and renders
    # none (`_chip.html.erb`), which is the shape the demo's own categories are in.
    it "gives a chip's Use this button the width of the chip", :aggregate_failures do
      phone = create(:item, category: groceries, name: "Phone")
      [2, 1].each { |back| create(:entry, item: phone, amount: 85, date: Date.current - back.months) }

      visit new_budget_path(category_id: groceries.id)

      chip = page.find("[data-chip]").native.rect
      button = page.find("[data-chip-button]").native.rect

      expect(button.width).to be > chip.width - 40
      expect(button.x + button.width).to be <= chip.x + chip.width
      expect(button.height).to be >= 40
    end
  end

  # ── THE DESKTOP THE MOBILE PASS MUST NOT MOVE ─────────────────────────────────────────────────
  #
  # ** A PADDING PIN, BECAUSE A MOBILE PASS ALREADY DRIFTED THIS ONCE. ** Adding `p-4` to the step
  # cards was spelled `p-4 sm:p-5`, which quietly took 24px of desktop padding down to 20 on every
  # step of this form — a change nobody asked for, in a commit whose report said the desktop was
  # unchanged. The value is asserted through Selenium's own geometry: the inset from the card's box
  # to its heading's is the padding plus the card's 1px border.
  describe "at a desktop width" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 1440, height: 900, deviceScaleFactor: 1, mobile: false
      )
    end

    it "keeps 24px of padding inside each step card", :aggregate_failures do
      visit new_budget_path(category_id: groceries.id)

      expect(page).to have_content("1. What is this rule for, and how much?")

      card = page.find("[data-step='1']").native.rect
      heading = page.find("[data-step='1'] h2").native.rect

      expect(heading.x - card.x).to eq(25)
    end
  end
end
