# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Details Card", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "with explicit color" do
    let!(:category) { create(:category, category_type: "expense", user: user, color: "#123456") }

    before do
      base_date = Date.current.beginning_of_month
      groceries = create(:item, category: category, name: "Groceries")
      dining = create(:item, category: category, name: "Dining")
      create(:entry, item: groceries, amount: 10, date: base_date.prev_month + 3.days)
      create(:entry, item: dining, amount: 20, date: base_date + 5.days)
      create(:entry, item: groceries, amount: 30, date: base_date.next_month + 2.days)
      visit category_path(category)
    end

    it "shows accurate type, overall counts, and created date", :aggregate_failures do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Number of Items")
      expect(page).to have_content("2")
      expect(page).to have_content("Total Entries")
      expect(page).to have_content("3")
      expect(page).to have_content(category.created_at.strftime("%b %d, %Y"))
    end
  end

  describe "tracked toggle", :aggregate_failures do
    let!(:category) { create(:category, :expense, user: user) }

    it "shows tracked by default and toggles off when clicked" do
      visit category_path(category)

      expect(page).to have_content("Tracked")
      expect(page).to have_css("button.bg-brand")

      find("dt", text: "Tracked").ancestor(".py-3").find("button").click

      expect(page).to have_css("button.bg-gray-300")
      expect(category.reload.tracked).to be false
    end

    it "toggles an untracked category back on" do
      category.update!(tracked: false)
      visit category_path(category)

      expect(page).to have_css("button.bg-gray-300")

      find("dt", text: "Tracked").ancestor(".py-3").find("button").click

      expect(page).to have_content("Tracked")
      expect(page).to have_css("button.bg-brand")
      expect(category.reload.tracked).to be true
    end
  end

  describe "without color" do
    let!(:category) { create(:category, category_type: "income", user: user, color: nil) }

    before { visit category_path(category) }

    it "shows default color when not set", :aggregate_failures do
      expect(page).to have_content("Default")
      # Default swatch uses fallback color #C9C78B
      expect(page).to have_css("span[style*='#C9C78B']")
    end
  end
end
