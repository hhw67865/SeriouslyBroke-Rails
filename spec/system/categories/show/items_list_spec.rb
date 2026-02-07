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

    it "updates when navigating to next month via navbar" do
      find("button[title='Next month']").click

      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(200)}")
      expect(page).to have_content("-#{ActionController::Base.helpers.number_to_currency(100)}")
    end

    it "Edit link works for items" do
      within(find("tr", text: "Groceries")) do
        click_link "Edit"
      end
      expect(page).to have_current_path(edit_item_path(groceries_item))
    end

    it "View button toggles inline entries and shows correct data" do
      expect(page).not_to have_css("[data-shared--toggle-target='content']:not(.hidden)")

      within(find("tbody", text: "Groceries")) do
        click_button "View"

        # Verify entry data is displayed
        expect(page).to have_content((base_date + 2.days).strftime("%b %d, %Y"))
        expect(page).to have_content(ActionController::Base.helpers.number_to_currency(100))

        click_button "Hide"
      end

      expect(page).not_to have_css("[data-shared--toggle-target='content']:not(.hidden)")
    end

    it "shows entries scoped to the correct item" do
      within(find("tbody", text: "Groceries")) { click_button "View" }
      within(find("tbody", text: "Dining")) { click_button "View" }

      # Groceries entry details
      groceries_row = find("tbody", text: "Groceries")
      expect(groceries_row).to have_content((base_date + 2.days).strftime("%b %d, %Y"))
      expect(groceries_row).to have_content(ActionController::Base.helpers.number_to_currency(100))

      # Dining entry details
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

  describe "savings items list", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user) }
    let!(:category) { create(:category, category_type: "savings", user: user, savings_pool: pool, name: "Emergency Fund") }
    let!(:transfer_item) { create(:item, category: category, name: "Transfer") }

    before do
      create(:entry, item: transfer_item, amount: 300, date: base_date + 7.days)
      visit category_path(category, month: base_date.month, year: base_date.year)
    end

    it "shows brand-colored positive amounts for savings" do
      expect(page).to have_content(ActionController::Base.helpers.number_to_currency(300))
    end
  end
end
