# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Cards", type: :system do
  def currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  let!(:user) { create(:user) }

  # Shared dates based on current month
  let(:base_date) { Date.current.beginning_of_month }
  let(:next_date) { base_date.next_month }
  let(:prev_date) { base_date.prev_month }

  before do
    sign_in user, scope: :user
  end

  # THE CARD'S CAP ARM IS DELETED (plan 3, task 3). Every expense category points at a pool now, so
  # the card takes its pooled arm — "Spent <period>" and the pool's name — and the "Monthly Budget
  # $150.00 / $1,000.00 · 15% used" arm it used to take has no rule left to read. The figures under
  # test move from the cap's percentage to the spending itself, which is the half the card still
  # renders and the half the month navigation is about.
  describe "expense card shows the period's spending and links to show", :aggregate_failures do
    let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let!(:expense_category) { create(:category, category_type: "expense", user: user, name: "Food", pool: checking) }
    let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
    let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }

    before do
      # Month A entries (total 150)
      create(:entry, item: groceries_item, amount: 100, date: base_date + 2.days)
      create(:entry, item: dining_item, amount: 50, date: base_date + 10.days)
      # Previous month entries (total 120)
      create(:entry, item: groceries_item, amount: 70, date: prev_date + 3.days)
      create(:entry, item: dining_item, amount: 50, date: prev_date + 9.days)
      # Month B entries (total 300)
      create(:entry, item: groceries_item, amount: 200, date: next_date + 5.days)
      create(:entry, item: dining_item, amount: 100, date: next_date + 12.days)

      visit categories_path(type: "expense", month: base_date.month, year: base_date.year)
    end

    it "displays the period's spending, its pool and the top items for selected month" do
      expect(page).to have_content(currency(150))
      expect(page).to have_content("Pool: Checking")
      expect(page).to have_no_content("% used")

      # Top items with amounts (expense shows negative sign)
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")
      expect(page).to have_content("-#{currency(100)}")
      expect(page).to have_content("-#{currency(50)}")

      find("div.group.cursor-pointer", text: expense_category.name).click
      expect(page).to have_current_path(category_path(expense_category))
    end

    it "updates the spending when navigating to next month via navbar and keeps type" do
      find("button[title='Next month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(300))
      expect(page).to have_content("-#{currency(200)}")
      expect(page).to have_content("-#{currency(100)}")
    end

    it "updates the spending when navigating to previous month via navbar" do
      find("button[title='Previous month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(120))
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

  # THE SAVINGS CARD IS DELETED WITH THE TYPE (plan 3, task 5). Two examples read a "Monthly
  # Contribution" figure, a "Savings Pool: Main Pool" line and plain (unsigned) top-item amounts off
  # a card arm that no longer exists — money reaches a goal as a `PoolMovement`, and the goal's own
  # page lists them. The expense and income card arms above make the same month-navigation claim
  # over the two types that survive.
end
