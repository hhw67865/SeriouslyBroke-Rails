# frozen_string_literal: true

require "rails_helper"

# The Budget page is where the give-way order is set, and this is the file that says what that
# means.
#
# The list is PRIORITY order, and the give-way order is Home's: the type ranks first there and no
# arrow here can reach it, so what these controls set is the tie-break inside a kind. The page draws
# the number the buttons write.
#
# Through the ▲▼ buttons, deliberately: they are plain forms carrying the whole order, so they are
# the path that works with scripting off, and the drag controller builds the same `category_ids[]`
# out of the DOM and submits the same PATCH. The one `:js` example is the one whose subject IS the
# drag.
RSpec.describe "Budget page reorder", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  around { |example| travel_to(today) { example.run } }

  # Two types, not one: both rules `usage` is the one shape where the give-way order and the
  # priority order agree, so a list drawn on the wrong key would look right on every example here.
  # Groceries is a BILL at priority 0 and Fun Money a CHOICE at priority 1.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 500)
    sign_in user, scope: :user
    rule_on("Groceries", amount: 400, type: :bill, priority: 0)
    rule_on("Fun Money", amount: 300, type: :choice, priority: 1)
    visit budget_page_path
  end

  def rule_on(name, amount:, type: :usage, priority: 0)
    create(
      :rule,
      :rate,
      rule_type: type,
      amount: amount,
      starts_on: Date.new(2026, 1, 1),
      category: create(:category, user: user, name: name, priority: priority)
    )
  end

  # Selenium's own `drag_and_drop` does not drive HTML5 drag events, so the four the controller
  # listens for are dispatched directly.
  def drop_the_first_card_below_the_second
    page.execute_script(<<~JS)
      const [first, second] = document.querySelectorAll("[data-category-row]")
      const transfer = new DataTransfer()
      const fire = (element, type, extra = {}) =>
        element.dispatchEvent(new DragEvent(type, { bubbles: true, dataTransfer: transfer, ...extra }))

      fire(first, "dragstart")
      fire(second, "dragover", { clientY: Math.round(second.getBoundingClientRect().bottom) })
      fire(second, "drop")
      fire(first, "dragend")
    JS
  end

  def rows = page.all("[data-category-row]").pluck("data-category-row")
  def row(name) = find("[data-category-row='#{name}']")
  def fill_order = user.categories.in_fill_order.pluck(:name)

  describe "moving a category up the order", :aggregate_failures do
    it "changes the order of the cards" do
      expect(rows).to eq(["Groceries", "Fun Money"])

      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(rows).to eq(["Fun Money", "Groceries"])
    end

    # Three assertions, and the third is the one a sign error would make false: the moved category's
    # own number changed, and the untouched one's moved only because the list did.
    it "writes the new order rather than only redrawing the cards" do
      expect(fill_order).to eq(["Groceries", "Fun Money"])

      click_button "Move Fun Money up"
      expect(page).to have_content("Your money fills them in that order now.")

      expect(fill_order).to eq(["Fun Money", "Groceries"])
      expect(user.categories.find_by!(name: "Fun Money").priority).to eq(0)
    end

    # This is the screen where priority is set, so the number is on the row: it is what these arrows
    # write and what "the highest number gives way first" is about.
    it "restates each category's new position on the page it comes back to" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      within(row("Fun Money")) { expect(page).to have_content("priority 0") }
      within(row("Groceries")) { expect(page).to have_content("priority 1") }
    end
  end

  # ▼ is not ▲ read backwards: each button carries its own already-swapped list, and a helper that
  # got the sign wrong would move the wrong row while still producing a valid order.
  it "arrives at the same order by moving the other one down", :aggregate_failures do
    click_button "Move Groceries down"

    expect(page).to have_content("Your money fills them in that order now.")
    expect(rows).to eq(["Fun Money", "Groceries"])
  end

  # Both directions on both rows, on one screen: an unconditionally disabled pair would pass half of
  # this and an unconditionally enabled one the other half.
  it "offers no move off either end", :aggregate_failures do
    within("[data-category-list]") do
      expect(page).to have_button("Move Groceries up", disabled: true)
      expect(page).to have_button("Move Groceries down", disabled: false)
      expect(page).to have_button("Move Fun Money up", disabled: false)
      expect(page).to have_button("Move Fun Money down", disabled: true)
    end
  end

  # The drag is the subject here, and nothing else on this page can be its stand-in — every other
  # example goes through the buttons, which reach the same endpoint. The last statement is a Capybara
  # query and not `execute_script`: a JS call as the final act leaves the session in a state the
  # teardown does not survive here.
  it "submits the order the cards were dropped in", :aggregate_failures, :js do
    expect(rows).to eq(["Groceries", "Fun Money"])

    drop_the_first_card_below_the_second

    expect(page).to have_content("Your money fills them in that order now.")
    expect(rows).to eq(["Fun Money", "Groceries"])
  end
end
