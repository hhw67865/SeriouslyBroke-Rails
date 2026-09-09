# frozen_string_literal: true

require "rails_helper"

# THE BUDGET PAGE IS WHERE THE GIVE-WAY ORDER IS SET (spec §8), and this is the file that says what
# that means.
#
# ── ** THE LIST IS PRIORITY ORDER, AND THE GIVE-WAY ORDER IS HOME'S (fix round MAJOR-1). ** For one
# commit this page drew the give-way order — type first, then priority — and it could not be dragged:
# the type ranks first and no arrow can reach it, so moving a card produced a list in the same order
# under a flash saying it had changed, and moved a DIFFERENT category's priority. The page draws the
# number these buttons write; `spec/system/home/this_period_spec.rb` and
# `budget_page_presenter_spec` pin that the same rows read the other way round on Home.
#
# ── IT IS A GIVE-WAY ORDER, NOT A FILL ORDER (computed-claims spec §§5-6), and that changes what
# this file can honestly measure. Nothing hands money out any more: a category's money is a CLAIM
# computed from its rules (`ClaimCalculator`/`ClaimLedger`), and every claim is stated in full
# whether or not the money is there. So priority no longer decides who gets filled first — it
# decides WHO GIVES WAY when the claims outrun the money, which is the order the shortfall walks in
# reverse.
#
# ** THE MONEY HALF IS NOW THE PERSISTED ORDER. ** "sends the money to the category that moved up"
# read `AllocationCalculator#rows` — the waterfall — and asserted which envelope the last dollar
# reached. There is no waterfall and no envelope, so the example asserts the thing the button
# actually writes: `categories.priority`, read back off the database rather than off the page that
# ordered it. That is still not one screen agreeing with itself, which was the whole point of
# refusing to read the order off the DOM; it is simply the durable half of the same claim. What the
# order MEANS for the money is pinned where the money is computed, in the claim specs and in
# `spec/system/home/trouble_spec.rb`'s `:shortfall` arm, which walks the give-way list.
#
# ── AND THE BANDS ARE GONE WITH THE PER-ACCOUNT FILL. Two examples went with them, named in
# "the ends of the order" below.
#
# THROUGH THE ▲▼ BUTTONS, deliberately. They are plain forms carrying the whole order, so they are
# the path that works with scripting off; the drag controller builds the same `category_ids[]` out
# of the DOM and submits the same PATCH. Testing the buttons tests the endpoint, the refusal and
# the fill without synthesising HTML5 drag events.
#
# `Capybara.exact` is unset in this suite, so every row assertion is scoped to its group — an
# unscoped `have_content("Groceries")` matches a heading, a rule row and the nav.
RSpec.describe "Budget page reorder", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 500)
  end

  # ** TWO TYPES, NOT ONE, AND THAT IS THE FIX ROUND'S FIXTURE (MAJOR-1). ** Both rules were `usage`
  # here, which is the one shape where the give-way order and the priority order agree — so a list
  # drawn on the wrong key looked right on every example in this file. Groceries is a BILL at
  # priority 1 and Fun Money a CHOICE at priority 2, which give-way ranks `[Fun Money, Groceries]`
  # (choice gives way first, whatever the numbers say) and priority ranks `[Groceries, Fun Money]`.
  # The list draws the second, because the second is what these arrows write.
  #
  # $500 of available against $700 of rules: the user is $200 short, so the order is the only thing
  # deciding who goes without.
  before do
    sign_in user, scope: :user
    holder("Groceries", rate: 400, priority: 1, type: :bill)
    holder("Fun Money", rate: 300, priority: 2, type: :choice)
    deposit(500)
    visit budget_page_path
  end

  describe "moving a category up the fill order", :aggregate_failures do
    # ** THE LIST IS PRIORITY ORDER, WHICH IS WHAT THESE ARROWS WRITE (fix round MAJOR-1). ** The
    # page opens `["Groceries", "Fun Money"]` — priority 1 then 2 — even though the give-way walk
    # reaches Fun Money first, because it is a choice. Moving Fun Money UP the list is moving it up
    # the priority order, and the two words mean one thing again.
    it "changes the order of the cards" do
      expect(cards).to eq(["Groceries", "Fun Money"])

      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries"])
    end

    # ** THE DEFECT THIS ROUND FIXED, AS AN EXAMPLE (MAJOR-1). ** Under the give-way list the page
    # drew `[Fun Money, Groceries]`; "move Fun Money down" reversed that to `[Fun Money, Groceries]`
    # on the wire, `apply_fill_order` wrote Fun Money 0 and Groceries 1, and the page came back
    # IDENTICAL under a flash saying the order had changed — while GROCERIES' priority had moved
    # though the user never touched it. Three assertions, and the third is the one that was false:
    # the moved category's own number changed, the untouched one's did NOT, and the list shows it.
    it "moves the dragged category's number and leaves the other's alone", :aggregate_failures do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries"])
      expect(user.categories.find_by!(name: "Fun Money").priority).to eq(0)
      expect(user.categories.find_by!(name: "Groceries").priority).to eq(1)
    end

    # ** THE NUMBER IS STILL ON THE ROW, AND IT IS NOT DECORATION. ** This is the screen where
    # priority is SET: the number is what these arrows write, what the category form's own field
    # says, and what "the highest number gives way first" is about. It sits beside the handle and is
    # hidden below `sm`, where the row keeps handle · name · dots · claimed (§4).
    it "restates each category's new position on the page it comes back to" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      within(group("Fun Money")) { expect(page).to have_content("priority 0") }
      within(group("Groceries")) { expect(page).to have_content("priority 1") }
    end

    # THE DATABASE, NOT THE LIST ON SCREEN. $500 of income cannot cover $700 of rules, so exactly
    # one of the two gives way — and which one is what this button decides, by writing `priority`.
    # Read back off the model's own give-way scope rather than off the page that ordered it: the
    # page is what is being ordered, and asking it what the order means would be one screen
    # agreeing with itself.
    # ** THE DATABASE, NOT THE LIST ON SCREEN, AND THE TWO NOW READ THE SAME WAY ROUND (fix round
    # MAJOR-1). ** `in_fill_order` is `[priority, name]` ascending and so is the list, so this is the
    # durable half of the same claim rather than the mirror of it — read back off the model instead
    # of off the page that ordered it, because the page is what is being ordered.
    it "writes the new order rather than only redrawing the cards" do
      expect(fill_order).to eq(["Groceries", "Fun Money"])

      click_button "Move Fun Money up"
      expect(page).to have_content("Your money fills them in that order now.")

      expect(fill_order).to eq(["Fun Money", "Groceries"])
    end
  end

  # ▼ IS NOT ▲ READ BACKWARDS: each button carries its own already-swapped list, and a helper
  # that got the sign wrong would move the wrong row while still producing a valid order.
  describe "moving a category down the fill order", :aggregate_failures do
    it "arrives at the same order as moving the other one up" do
      click_button "Move Groceries down"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries"])
    end
  end

  describe "the ends of the order", :aggregate_failures do
    # TWO EXAMPLES ARE DELETED HERE (two-ledger spec §2). "leaves the same user's other account
    # exactly where it was" and "keeps each account's order to itself" both pinned that a reorder
    # in one band could not reach another — a property of the per-account fill, which the
    # single-root ordering replaced. There is one list, so there is no second one to leak into and
    # no fixture that could express the leak.

    # Both directions on both rows, on one screen: an unconditionally disabled pair would pass
    # half of this and an unconditionally enabled one the other half.
    # THE ENDS ARE THE ENDS OF THE LIST AS DRAWN, and the list is priority order — so Groceries
    # (priority 1) is the top row and cannot move up, and Fun Money (2) is the bottom one and cannot
    # move down.
    it "offers no move off either end" do
      within("[data-category-list]") do
        expect(page).to have_button("Move Groceries up", disabled: true)
        expect(page).to have_button("Move Groceries down", disabled: false)
        expect(page).to have_button("Move Fun Money up", disabled: false)
        expect(page).to have_button("Move Fun Money down", disabled: true)
      end
    end

    # ** A CATEGORY THE ENDPOINT WOULD REFUSE DRAWS NO HANDLE AT ALL (§4). ** The list is every
    # expense category now, and `Category.apply_fill_order` accepts only
    # `in_fill_order.with_a_rule`; a rule-less category with arrows would be a control whose every
    # use is refused, with a message about the order the page had just drawn.
    it "draws no arrows on a category the reorder cannot include", :aggregate_failures do
      create(:category, :expense, :funded, user: user, name: "Vacation", priority: 3)
      visit budget_page_path

      expect(cards).to include("Vacation")
      within(group("Vacation")) do
        expect(page).to have_no_button("Move Vacation up")
        expect(page).to have_no_button("Move Vacation down")
      end
    end
  end

  # ** A CANCELLED DRAG PUTS EVERY ROW BACK, NOT JUST THE DRAGGABLE ONES (fix wave — LOW-2). **
  #
  # `reorder_controller#restore` re-inserted each row TARGET before the hidden form in turn, which
  # restores the draggable cards' order relative to each other and shoves every non-target row out
  # from between them — and the list holds non-targets by design: `CategoryRow#reorderable?` is
  # `holder? && ruled?`, so a category carrying a rule that has stopped holding money renders a card
  # with no handle. Pressing Escape mid-drag therefore left the page rearranged in a way no drop had
  # asked for and no PATCH had recorded, which is the worst kind of wrong: the screen disagreeing
  # with the database with no act in between. Each row is restored to its own recorded `nextSibling`
  # now.
  #
  # ** THE DRAG IS SYNTHESISED, WHICH THIS FILE OTHERWISE REFUSES TO DO — and the reason it is
  # allowed here is that the drag is the SUBJECT. ** Every other example goes through the ▲▼ buttons
  # because they carry the same `category_ids[]` to the same endpoint, so the buttons test the write.
  # Nothing is written here: the whole claim is what the DOM looks like after a drag that was
  # abandoned, and no button can abandon one. Selenium's own `drag_and_drop` does not drive HTML5
  # drag events, so the three events the controller listens for are dispatched directly.
  #
  # THE LAST STATEMENT IS A CAPYBARA QUERY AND NOT `evaluate_script` (CLAUDE.md's first flake cause,
  # narrow-viewport note): a JS call as the final act leaves the session in a state the teardown does
  # not survive here.
  describe "a drag the user abandons", :aggregate_failures do
    # THE ROW THAT IS NOT A TARGET, planted BETWEEN the two that are. `[priority, name]` puts a
    # priority-1 "Vacation" after "Groceries" and before priority-2 "Fun Money", and `update_column`
    # clears the funding stamp WITHOUT touching the rule — the shape is "a rule on a category that
    # stopped holding money", which the Budget page draws as a handle-less card.
    let!(:stalled) do
      holder("Vacation", rate: 100, priority: 1).tap do |category|
        # rubocop:disable Rails/SkipsModelValidations -- the shape is illegal to WRITE and legal to
        # HOLD: `BudgetProposal` stamps `funded_since` when a rule is accepted, and a category that
        # later stops holding money keeps its rule. `update!` would run the model's own guards on a
        # state a user reaches by a different door.
        category.update_column(:funded_since, nil)
        # rubocop:enable Rails/SkipsModelValidations
      end
    end

    # dragstart on Fun Money, dragover the TOP half of Groceries (so `#over` inserts before it), then
    # dragend with no `drop` — which is exactly what Escape produces.
    def drag_and_abandon = <<~JS
      const list = document.querySelector("[data-category-list]");
      const row = (name) => list.querySelector(`[data-category-row="${name}"]`);
      const transfer = new DataTransfer();
      const fire = (element, type, extra = {}) => element.dispatchEvent(
        new DragEvent(type, Object.assign({ bubbles: true, cancelable: true, dataTransfer: transfer }, extra))
      );
      const dragged = row("Fun Money");
      const over = row("Groceries");
      fire(dragged, "dragstart");
      fire(over, "dragover", { clientY: over.getBoundingClientRect().top + 1 });
      fire(dragged, "dragend");
    JS

    it "leaves the list exactly as it found it, handle-less rows included" do
      visit budget_page_path

      expect(stalled.reload.funded_since).to be_nil
      expect(cards).to eq(["Groceries", "Vacation", "Fun Money"])
      within(group("Vacation")) { expect(page).to have_no_button("Move Vacation up") }

      page.execute_script(drag_and_abandon)

      expect(cards).to eq(["Groceries", "Vacation", "Fun Money"])
    end

    # THE OTHER DIRECTION, so the example above cannot pass against a controller whose drag does
    # nothing at all: the same three events with a `drop` in the middle DO reorder the list, and the
    # PATCH that follows writes the new priorities.
    it "reorders and writes when the same drag is dropped" do
      visit budget_page_path

      page.execute_script(
        drag_and_abandon.sub(
          'fire(dragged, "dragend");',
          'fire(over, "drop"); fire(dragged, "dragend");'
        )
      )

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries", "Vacation"])
    end
  end

  private

  def holder(name, rate:, priority:, type: :usage)
    category = create(:category, :expense, :funded, user: user, name: name, priority: priority)
    create(:budget, :per_period_rate, category: category, amount: rate, rule_type: type)
    category
  end

  def deposit(amount)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # THE ORDER AS THE DATABASE HOLDS IT — `Category.in_fill_order`'s own `[priority, name]`, which is
  # also the order the page draws, so a rewrite that only renumbered the cards on screen would not
  # satisfy it. Never read off the page, for the reason given on the example that uses it.
  def fill_order
    user.reload.categories.in_fill_order.with_a_rule.pluck(:name)
  end

  # THE HOOK IS `data-category-row` SINCE THE PAGE BECAME ONE LIST OF EVERY CATEGORY (two-shapes
  # spec §4) — `data-category-group` was the group CARD's, and the card is a row now.
  def group(name) = find("[data-category-row='#{name}']")

  def cards = page.all("[data-category-row]").pluck("data-category-row")
end
