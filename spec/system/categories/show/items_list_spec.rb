# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Items This Month", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }
  let(:next_date) { base_date.next_month }

  before { sign_in user, scope: :user }

  describe "expense items list", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:groceries_item) { create(:item, category: category, name: "Groceries") }
    let!(:dining_item) { create(:item, category: category, name: "Dining") }

    before do
      # Month A entries
      create(:entry, item: groceries_item, amount: 100, date: base_date + 2.days)
      create(:entry, item: dining_item, amount: 50, date: base_date + 10.days)
      # Month B entries
      create(:entry, item: groceries_item, amount: 200, date: next_date + 5.days)
      create(:entry, item: dining_item, amount: 100, date: next_date + 12.days)

      visit category_path(category, month: base_date.month, year: base_date.year)
    end

    it "shows month-scoped items and amounts for selected month" do
      expect(page).to have_content("Items This Month")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")

      # Expense uses negative sign on amounts
      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(100)}")
      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(50)}")
    end

    # `first`: the sidebar renders the date selector twice — mobile and desktop — and both submit
    # the same GET, so under Rack::Test either control is the control.
    it "updates when navigating to next month via navbar" do
      first("button[title='Next month']").click

      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(200)}")
      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(100)}")
    end

    it "Edit link works for items" do
      within(find("tr", text: "Groceries")) do
        click_link "Edit"
      end
      expect(page).to have_current_path(edit_item_path(groceries_item))
    end

    # `:js`: the row's entries are revealed by app--category--expandable, so the button does
    # nothing at all without a browser and "Hide" never appears.
    it "View button toggles inline entries and shows correct data", :js do
      expect(page).to have_no_css("[data-app--category--expandable-target='content']:not(.hidden)")

      within(find("tbody", text: "Groceries")) do
        click_button "View"

        expect(page).to have_content((base_date + 2.days).strftime("%b %d, %Y"))
        expect(page).to have_content(ActionController::Base.helpers.number_to_currency(100))

        click_button "Hide"
      end

      expect(page).to have_no_css("[data-app--category--expandable-target='content']:not(.hidden)")
    end

    it "renders each item's own entries in its own row" do
      groceries_row = find("tbody", text: "Groceries")
      expect(groceries_row).to have_content((base_date + 2.days).strftime("%b %d, %Y"))
      expect(groceries_row).to have_content(ActionController::Base.helpers.number_to_currency(100))

      dining_row = find("tbody", text: "Dining")
      expect(dining_row).to have_content((base_date + 10.days).strftime("%b %d, %Y"))
      expect(dining_row).to have_content(ActionController::Base.helpers.number_to_currency(50))
    end
  end

  describe "income items list", :aggregate_failures do
    let!(:category) { create(:category, category_type: "income", user: user, name: "Salary") }
    let!(:paycheck_item) { create(:item, category: category, name: "Paycheck") }

    before do
      create(:entry, item: paycheck_item, amount: 700, date: base_date + 3.days)
      visit category_path(category, month: base_date.month, year: base_date.year)
    end

    it "shows positive amounts for income" do
      expect(page).to have_content("+#{ActionController::Base.helpers.number_to_currency(700)}")
    end
  end
end
