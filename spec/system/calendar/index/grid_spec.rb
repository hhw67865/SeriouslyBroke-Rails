# frozen_string_literal: true

require "rails_helper"

# TWO TOTALS PER DAY, NOT THREE (plan 3, task 5). The grid's columns are
# `CategoryTypeHelper::CATEGORY_TYPES`, so the savings one left with the enum value — and what a
# contribution BECAME does not arrive in its place: a `AccountMovement` is the user's own money
# changing pockets, not money entering or leaving their life. Both directions asserted below.
RSpec.describe "Calendar Index - Grid", type: :system do
  let!(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # The other end of the transfer: a SECOND ACCOUNT, because a movement now has an account on
  # both ends (two-ledger spec §5, Task 8). It was a savings POOL sitting inside Checking.
  let!(:savings_account) { create(:pool, :account, user: user, name: "Emergency Fund") }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }

  before { sign_in user, scope: :user }

  describe "weekday headers", :aggregate_failures do
    before { visit calendar_path }

    it "shows all seven days of the week" do
      ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].each do |day|
        expect(page).to have_content(day)
      end
    end
  end

  describe "calendar grid structure", :aggregate_failures do
    before { visit calendar_path }

    it "displays calendar grid" do
      expect(page).to have_css(".calendar-grid")
      expect(page).to have_css(".calendar-week-row")
    end
  end

  describe "day cells with entries", :aggregate_failures do
    before do
      expense_item = create(:item, category: expense_category)
      income_item = create(:item, category: income_category)

      create(:entry, item: expense_item, amount: 50.00, date: Date.current)
      create(:entry, item: income_item, amount: 1000.00, date: Date.current)
      # A $200 contribution ON THE SAME DAY, as the movement it is now. Nothing on this grid may
      # report it: the presenters read `Entry` and nothing else.
      create(:account_movement, from_pool: checking, to_pool: savings_account, amount: 200.00, date: Date.current)

      visit calendar_path
    end

    it "shows expense total in red" do
      expect(page).to have_css(".text-status-danger", text: "$50")
    end

    it "shows income total in green" do
      expect(page).to have_css(".text-status-success", text: "$1k")
    end

    # BOTH DIRECTIONS ON THE NO-MOVEMENTS RULE: the two entry totals ARE drawn, and the movement
    # of the same day is drawn nowhere and in no colour.
    #
    # SCOPED TO THE GRID, because `.text-brand-dark` is the app's chrome colour too — the sidebar
    # heading and the avatar carry it — so a page-wide negative would be asserting something about
    # the layout rather than about the calendar.
    it "draws nothing at all for the movement", :aggregate_failures do
      within(".calendar-grid") do
        expect(page).to have_no_css(".text-brand-dark")
        expect(page).to have_no_content("$200")
        expect(page).to have_content("$50")
        expect(page).to have_content("$1k")
      end
    end
  end

  describe "day cell navigation", :aggregate_failures do
    before { visit calendar_path }

    it "links day cells to weekly view" do
      today = Date.current.day.to_s
      day_link = find("a", text: /\A#{today}\z/, match: :first)
      day_link.click

      expect(page).to have_current_path(calendar_week_path(date: Date.current.strftime("%Y-%m-%d")))
    end
  end

  describe "adjacent month days", :aggregate_failures do
    before { visit calendar_path }

    it "styles days from adjacent months differently" do
      expect(page).to have_css(".calendar-adjacent")
    end
  end
end
