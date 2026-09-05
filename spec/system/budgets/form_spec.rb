# frozen_string_literal: true

require "rails_helper"

# THE RULE FORM, ONE OWNER (two-ledger spec §3) AND EVERY SHAPE (rules-own-the-budget spec §4).
#
# WHAT THIS FILE USED TO BE, THREE TIMES OVER. Every example was once about the monthly category CAP
# — a form reached as `/budgets/new?category_id=…`, a "Set spending limits for Groceries" heading, a
# "Prorate daily" checkbox — and all of it was deleted with the cap in plan 3. What replaced it was
# a POOL-mode rule form; that went with the pool layer. What is added here is the half the form
# never had: a hand-made rule could only ever be a per-period rate ("Rules form needs to be able to
# set the complex rules too, not just the per period catchall", Henry, 2026-09-04), and the controls
# reach every row of the shape table. THE TABLE IS TWO SHAPES NOW (two-shapes spec §2) — an allowance
# that resets, and money saved toward a day — so the "Unspent money" step and its Target are gone
# with `budgets.carries_over` and `budgets.target_amount` (§7).
#
# ONE BROWSER PASS PER SHAPE, and each asserts the COLUMNS rather than a flash: a form that posts
# the right words to a mapping that has quietly changed still says "successfully created".
RSpec.describe "Budgets Forms", type: :system do
  let(:user) { create(:user, :biweekly, typical_income: 2_400) }
  let!(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  before { sign_in user, scope: :user }

  # ---------------------------------------------------------------------------------------------
  # §2.1's seven rows, written by hand
  # ---------------------------------------------------------------------------------------------
  describe "writing every shape by hand", :aggregate_failures do
    let!(:vacation) { create(:category, :expense, :funded, user: user, name: "Vacation to Europe") }

    before do
      visit new_budget_path
      select "Groceries", from: "Category"
      choose "Usage"
    end

    # §2.1 row 1. THE FORM OPENS ON THIS SHAPE, so the only control it needs is the amount — which
    # is exactly what a hand-made rule meant before this task, and is now the default rather than
    # the ceiling.
    it "writes a per-period rate that resets" do
      fill_in "Rule Amount", with: "400"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      rule = groceries.budgets.sole
      expect(rule).to have_attributes(basis: "per_period", interval_months: nil, anchor_date: nil, amount: 400)
    end

    # ** ROWS 2, 3 AND 4 ARE DELETED WITH THE SHAPE THEY WROTE (two-shapes spec §2/§7). ** They were
    # the uncapped fund ("a number saved per period … that you could allow to infinitely grow"), the
    # goal that built toward a target, and the goal fed by hand at a $0 rate — all three written by
    # choosing "Builds up" and filling (or leaving blank) a Target. That step is gone from the form
    # and its two columns from the table: a fund IS a dated rule whose amount is its target, so a goal
    # is written as "$5,000 by Jun 1, 2027" and appears below as a one-off.

    # ** "Every month" IS NOT ON THE FORM ANY MORE (two-shapes §5's ruling). ** `monthly` with no due
    # date is a legal row and `SuggestionEngine` still writes one; it is not a shape people write by
    # hand, so the two options cover what they do write and `RuleForm.from` reads an existing one back
    # as "Every period". The example that wrote it by hand goes with the option.

    # §2 row 4 — the half-yearly bill, which could only ever arrive MEASURED from the suggestion panel
    # before this form. The checkbox is what adds the interval.
    it "writes a bill that repeats every N months from a date" do
      fill_in "Rule Amount", with: "600"
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
      fill_in "Rule Amount", with: "600"
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
      fill_in "Rule Amount", with: "5000"
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
      fill_in "Rule Amount", with: "75"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to be_choice
    end

    it "lands one on a savings category too" do
      select "Vacation to Europe", from: "Category"
      fill_in "Rule Amount", with: "60"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(vacation.budgets.sole.amount).to eq(60)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # What each choice reveals, and what it hides
  # ---------------------------------------------------------------------------------------------
  describe "the reveals", :aggregate_failures do
    before do
      visit new_budget_path
      select "Groceries", from: "Category"
    end

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

    # ** THE "Unspent money" EXAMPLES ARE DELETED WITH THE STEP (two-shapes §5/§7). ** Four of them
    # pinned that the radios and the Target were on screen for a dateless schedule, hidden AND
    # DISABLED for a dated one (the state a browser with no JavaScript is served), live again on the
    # way back, and that the Target appeared only under "Builds up". There is no such control: a fund
    # IS a dated rule, so there is nothing about unspent money left to ask and nothing to disable.

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
      fill_in "Rule Amount", with: "400"
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

    # "PAYS" IS FILTERED BY THE CATEGORY IN FORCE, in the browser and with no round trip. Every item
    # the user owns is really in the document — which is what lets a browser with no JavaScript
    # submit any of them and get `Budget#item_must_belong_to_category`'s legible 422 — so the filter
    # has to be asserted on what is SELECTABLE rather than on what exists.
    it "offers only the chosen category's items under Pays" do
      create(:item, category: groceries, name: "Milk")
      utilities = create(:category, :expense, :funded, user: user, name: "Utilities")
      create(:item, category: utilities, name: "Power")

      visit new_budget_path
      select "Groceries", from: "Category"

      expect(selectable_items).to eq(["The whole category", "Milk"])
      expect(rendered_items).to include("Power")

      select "Utilities", from: "Category"

      expect(selectable_items).to eq(["The whole category", "Power"])
    end

    it "lands the rule on the item it says it pays" do
      milk = create(:item, category: groceries, name: "Milk")

      visit new_budget_path
      select "Groceries", from: "Category"
      select "Milk", from: "Pays"
      choose "Bill"
      fill_in "Rule Amount", with: "90"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole.item).to eq(milk)
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The refusals a user can actually meet
  # ---------------------------------------------------------------------------------------------
  describe "refusals", :aggregate_failures do
    before do
      visit new_budget_path
      select "Groceries", from: "Category"
    end

    # THE OWNER-LESS SAVE IS STILL REFUSED, and on `:base` where the form renders base errors —
    # the picker offers a blank because "I have not chosen yet" is a real state, not because a rule
    # may have no owner.
    it "refuses the save when no category is chosen, and says why" do
      visit new_budget_path
      choose "Usage"
      fill_in "Rule Amount", with: "500"
      click_button "Create rule"

      expect(page).to have_css(".bg-status-danger-light", text: "must belong to a category")
      expect(page).to have_select("Category")
      expect(Budget.count).to eq(0)
    end

    # EVERY RULE HAS A TYPE (§3) and the give-way order is built on it, so no radio is preselected
    # on a hand-made rule and the save is refused until one is.
    it "refuses a rule with no type chosen" do
      fill_in "Rule Amount", with: "400"
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
      fill_in "Rule Amount", with: "600"
      click_button "Create rule"

      expect(page).to have_content("When it is needed needs the number of months")
      expect(Budget.count).to eq(0)
    end

    it "refuses a dated rule with no date, under When it is needed" do
      choose "Usage"
      choose "By a date"
      fill_in "Rule Amount", with: "600"
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
      expect(page).to have_content("Edit rule")
      expect(page).to have_content("What Groceries claims each period")
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
    # form does not carry it; the rule keeps its owner because the ROW has one.
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
  # (fix round 1 — MED-5; two-shapes §5's ruling). ** `SuggestionEngine` still writes "$260 every
  # month", and `RuleForm.from` reads it back as "Every period" — so the record the page renders has
  # ALREADY been re-shaped, and every hint derived from it would call a month's figure a period's.
  # Saving it unchanged really does convert the rule, and `Budget#steady_ask` prices the two
  # differently: $260 a month is $120.00 a fortnight.
  #
  # THE FORM SAYS BOTH THINGS: the hint names the unit the FIGURE is in, and the note under it names
  # what saving would do. Asserted on the rendered page, because the whole point is what a person
  # reading the form is told before they press the button.
  describe "editing a monthly rule the form does not offer", :aggregate_failures do
    let!(:monthly) { create(:budget, :rate, category: groceries, amount: 260, rule_type: :usage) }

    before { visit edit_budget_path(monthly) }

    it "opens as Every period, in the rule's own unit, and warns what saving would do" do
      expect(page).to have_checked_field("Every period")
      expect(page).to have_field("Amount", with: "260.0")
      expect(page).to have_content("What this rule asks for a month.")
      expect(find("[data-monthly-conversion]")).to have_content(
        "This rule is $260.00 a month; saving it as every period would make it $260.00 a period"
      )
    end

    # THE OTHER DIRECTION, so the note is not a fixture of every edit form: an ordinary per-period
    # rule says nothing about months at all.
    it "says nothing of the sort on a rule whose words match its columns" do
      visit edit_budget_path(create(:budget, :per_period_rate, category: groceries, amount: 400, item: create(:item, category: groceries)))

      expect(page).to have_content("What this rule asks for per period.")
      expect(page).to have_no_css("[data-monthly-conversion]")
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The picker, and the two dead eras' controls
  # ---------------------------------------------------------------------------------------------
  describe "New rule form with no owner", :aggregate_failures do
    let!(:salary) { create(:category, :income, user: user, name: "Salary") }

    # A SAVINGS CATEGORY IS OFFERED and an INCOME one is not — §3's "typically no refill rule" is a
    # typically, and a goal a rate rule refills is the demo's own Retirement Supplement. Planted in
    # the `before` rather than as a `let!` because the picker's whole option list is the assertion:
    # no example names this record, they name the list it has to appear in.
    before do
      create(:category, :expense, :funded, user: user, name: "Vacation to Europe")
      create(:category, :expense, :funded, user: create(:user), name: "Their Rent")
      visit budget_page_path
    end

    # THE TWO NEGATIVES ARE THE OLD EXAMPLE'S SURVIVING HALF, and they are not redundant with the
    # picker assertion beside them: they guard against the two dead eras' controls coming back —
    # the cap's `prorated` checkbox and the pool picker. Neither column can be written any more, and
    # this is the screen where a regression restoring either would show up first.
    it "is reachable from the Budget page's own header, and offers no dead-era control" do
      click_link "New rule"

      expect(page).to have_current_path(new_budget_path)
      expect(page).to have_content("New rule")
      expect(page).to have_select("Category")
      expect(page).to have_no_select("Pool")
      expect(page).to have_no_field("Prorate daily")
    end

    # A RULE'S OWNER IS AN EXPENSE CATEGORY, never an income one — income lands in available and is
    # allocated out of it (§2), so a rule on one would claim money that category never holds. A
    # SAVINGS category IS offered: a goal a rate rule refills is the demo's own Retirement
    # Supplement.
    it "offers this user's expense categories, and nothing else" do
      click_link "New rule"

      expect(page).to have_select(
        "Category",
        options: ["Select a category", "Groceries", "Vacation to Europe"]
      )
      expect(salary.reload.budgets).to be_empty
    end

    # THE STAMP, THROUGH THE BROWSER (two-ledger spec §4). A rule is one of the two things that make
    # a category start holding its own money, and the hand-made path writes it exactly as the accept
    # flow does — `BudgetProposal` is the one writer, and `RuleForm#save` is the one door onto it.
    it "starts an unfunded category holding money from today" do
      unfunded = create(:category, :expense, user: user, name: "Coffee")

      click_link "New rule"
      select "Coffee", from: "Category"
      choose "Usage"
      fill_in "Rule Amount", with: "35.00"
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(unfunded.reload.funded_since).to eq(Date.current)
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
  # read. The idiom, and the measurements behind it, are in `spec/system/home/hero_spec.rb`.
  #
  # SELENIUM'S OWN GEOMETRY AND NO TRAILING `evaluate_script`: an example whose last statement runs
  # JS leaves the session in a state Capybara's teardown does not survive here.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # THE RADIO ROWS ARE THE THING AT RISK. Each is a control, a title and a line of help on one
    # line, which is the shape that pushes a page sideways when it cannot wrap — and there are two
    # such groups on this form where there were none before.
    it "fits the form and its radio rows inside a 375px viewport", :aggregate_failures do
      visit new_budget_path

      expect(page).to have_content("When is it needed?")
      expect(page).to have_field("Rule Amount")

      card = page.find("form[action=\"#{budgets_path}\"]").native.rect
      radio = page.find("label", text: "money saved up toward a day").native.rect

      expect(card.x + card.width).to be <= 375
      expect(radio.x + radio.width).to be <= card.x + card.width
    end
  end

  # ** WHAT IS SELECTABLE, NOT WHAT IS RENDERED. ** Every item the user owns is really in the
  # document — that is what lets a browser with no JavaScript submit any of them and meet
  # `Budget#item_must_belong_to_category`'s legible 422 — so `have_select(options:)` sees the whole
  # list whatever the filter did. The filter's own effect is the `disabled`/`hidden` pair the
  # controller sets, which is what a user can actually reach.
  def selectable_items
    item_options.reject(&:disabled?).map(&:text)
  end

  def rendered_items = item_options.map(&:text)

  def item_options = page.all("select[name='budget[item_id]'] option", visible: :all)
end
