# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Index - Grid", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
  let!(:savings_category) { create(:category, :savings, user: user, name: "Emergency Fund") }

  before { sign_in user, scope: :user }

  describe "weekday headers", :aggregate_failures do
    before { visit calendar_path }

    it "shows all seven days of the week" do
      %w[Sun Mon Tue Wed Thu Fri Sat].each do |day|
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
      savings_item = create(:item, category: savings_category)

      create(:entry, item: expense_item, amount: 50.00, date: Date.current)
      create(:entry, item: income_item, amount: 1000.00, date: Date.current)
      create(:entry, item: savings_item, amount: 200.00, date: Date.current)

      visit calendar_path
    end

    it "shows expense total in red" do
      expect(page).to have_css(".text-status-danger", text: "$50")
    end

    it "shows income total in green" do
      expect(page).to have_css(".text-status-success", text: "$1k")
    end

    it "shows savings total in brand color" do
      expect(page).to have_css(".text-brand-dark", text: "$200")
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
