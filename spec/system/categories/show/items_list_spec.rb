# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Items This Month", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }
  let(:next_date) { base_date.next_month }

  before { sign_in user }

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

    it "Edit and View links work for items" do
      # Click Edit within Groceries row, not the page header Edit
      within(find("tr", text: "Groceries")) do
        click_link "Edit"
      end
      expect(page).to have_current_path(edit_item_path(groceries_item))

      # Go back and test View within Groceries row
      visit category_path(category)
      within(find("tr", text: "Groceries")) do
        click_link "View"
      end
      expect(page).to have_current_path(entries_path(field: "item", q: groceries_item.name))
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
