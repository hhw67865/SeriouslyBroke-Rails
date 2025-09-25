# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Cards", type: :system do
  def currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  let!(:user) { create(:user) }

  # Shared dates
  let(:base_date) { Date.new(2025, 8, 1) }
  let(:next_date) { base_date.next_month }

  before do
    sign_in user
  end

  describe "expense card shows correct monthly budget and links to show", :aggregate_failures do
    let!(:expense_category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
    let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }

    before do
      # Create budget for expense category
      create(:budget, category: expense_category, amount: 1000)

      # Month A entries (total 150)
      create(:entry, item: groceries_item, amount: 100, date: base_date + 2.days)
      create(:entry, item: dining_item, amount: 50, date: base_date + 10.days)
      # Month B entries (total 300)
      create(:entry, item: groceries_item, amount: 200, date: next_date + 5.days)
      create(:entry, item: dining_item, amount: 100, date: next_date + 12.days)

      visit categories_path(type: "expense", month: base_date.month, year: base_date.year)
    end

    it "displays correct monthly budget, percentage, and top items for selected month" do
      # Budget totals and percentage
      expect(page).to have_content(currency(150))
      expect(page).to have_content("/ #{currency(1000)}")
      expect(page).to have_content("15% used")

      # Top items with amounts (expense shows negative sign)
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")
      expect(page).to have_content("-#{currency(100)}")
      expect(page).to have_content("-#{currency(50)}")

      find("div.group.cursor-pointer", text: expense_category.name).click
      expect(page).to have_current_path(category_path(expense_category))
    end

    it "updates budget info when navigating to next month via navbar and keeps type" do
      find("button[title='Next month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(300))
      expect(page).to have_content("30% used")
      expect(page).to have_content("-#{currency(200)}")
      expect(page).to have_content("-#{currency(100)}")
    end

    it "updates budget info when navigating to previous month via navbar" do
      find("button[title='Next month']").click # Go to September first
      find("button[title='Previous month']").click # Back to August

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(150))
      expect(page).to have_content("15% used")
    end
  end

  describe "income card shows correct monthly income and links to show", :aggregate_failures do
    let!(:income_category) { create(:category, category_type: "income", user: user, name: "Salary") }
    let!(:paycheck_item) { create(:item, category: income_category, name: "Paycheck") }
    let!(:bonus_item) { create(:item, category: income_category, name: "Bonus") }

    before do
      # Previous month baseline for % change (500)
      create(:entry, item: paycheck_item, amount: 500, date: base_date.prev_month + 5.days)
      # Current month (750)
      create(:entry, item: paycheck_item, amount: 500, date: base_date + 1.day)
      create(:entry, item: bonus_item, amount: 250, date: base_date + 15.days)
      # Next month (1000)
      create(:entry, item: paycheck_item, amount: 700, date: next_date + 3.days)
      create(:entry, item: bonus_item, amount: 300, date: next_date + 10.days)

      visit categories_path(type: "income", month: base_date.month, year: base_date.year)
    end

    it "displays correct monthly income, percentage change, and top items for selected month" do
      expect(page).to have_content(currency(750))
      # 50% up vs last month (750 vs 500)
      expect(page).to have_content("50%")

      # Top items with positive amounts
      expect(page).to have_content("Paycheck")
      expect(page).to have_content("Bonus")
      expect(page).to have_content("+#{currency(500)}")
      expect(page).to have_content("+#{currency(250)}")

      find("div.group.cursor-pointer", text: income_category.name).click
      expect(page).to have_current_path(category_path(income_category))
    end

    it "updates income info when navigating to next month via navbar" do
      find("button[title='Next month']").click

      expect(page).to have_content(currency(1000))
      expect(page).to have_content("+#{currency(700)}")
      expect(page).to have_content("+#{currency(300)}")
    end
  end

  describe "savings card shows correct monthly contribution and links to show", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Main Pool") }
    let!(:savings_category) { create(:category, category_type: "savings", user: user, savings_pool: pool, name: "Emergency Fund") }
    let!(:transfer_item) { create(:item, category: savings_category, name: "Transfer") }
    let!(:rollover_item) { create(:item, category: savings_category, name: "Rollover") }

    before do
      # Month A entries (total 250)
      create(:entry, item: transfer_item, amount: 200, date: base_date + 7.days)
      create(:entry, item: rollover_item, amount: 50, date: base_date + 14.days)
      # Month B entries (total 300)
      create(:entry, item: transfer_item, amount: 200, date: next_date + 1.day)
      create(:entry, item: rollover_item, amount: 100, date: next_date + 8.days)

      visit categories_path(type: "savings", month: base_date.month, year: base_date.year)
    end

    it "displays correct monthly contribution, savings pool, and top items for selected month" do
      expect(page).to have_content(currency(250))

      # Shows associated savings pool
      expect(page).to have_content("Savings Pool: Main Pool")

      # Top items with amounts (savings shows plain amounts)
      expect(page).to have_content("Transfer")
      expect(page).to have_content("Rollover")
      expect(page).to have_content(currency(200))
      expect(page).to have_content(currency(50))

      find("div.group.cursor-pointer", text: savings_category.name).click
      expect(page).to have_current_path(category_path(savings_category))
    end

    it "updates savings info when navigating to next month via navbar" do
      find("button[title='Next month']").click

      expect(page).to have_content(currency(300))
      expect(page).to have_content(currency(200))
      expect(page).to have_content(currency(100))
    end
  end
end
