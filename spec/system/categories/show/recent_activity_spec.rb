# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Recent Activity", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "recent entries list and navigation", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:item) { create(:item, category: category, name: "Groceries") }

    before do
      create(:entry, item: item, amount: 20, date: Date.current)
      visit category_path(category)
    end

    it "shows recent activity and links to View All Activity" do
      expect(page).to have_content("Recent Activity")
      expect(page).to have_content("Groceries")
      expect(page).to have_link("View All Activity")
      click_link "View All Activity"
      expect(page).to have_current_path(entries_path(field: "category", q: category.name))
    end
  end
end
