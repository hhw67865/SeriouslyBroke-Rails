# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items Manage - Index", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Food", user: user) }

  before { sign_in user, scope: :user }

  describe "page content", :aggregate_failures do
    let!(:item) { create(:item, name: "Groceries", category: category) }

    before do
      create_list(:entry, 3, item: item)
      visit category_items_path(category)
    end

    it "shows header with breadcrumbs and actions" do
      expect(page).to have_content("Manage Items")
      expect(page).to have_content("Food")
      expect(page).to have_link("New Item")
      expect(page).to have_link("Categories")
    end

    it "shows item details in table" do
      expect(page).to have_content("Groceries")
      expect(page).to have_content("3")
      expect(page).to have_link("Edit")
      expect(page).to have_link("Merge")
    end

    it "shows last active timestamp" do
      expect(page).to have_content("ago")
    end
  end

  describe "empty state", :aggregate_failures do
    it "shows empty message when no items" do
      visit category_items_path(category)

      expect(page).to have_content("No items in this category")
      expect(page).to have_link("Back to Category")
    end
  end

  describe "search", :aggregate_failures do
    it "filters items by name" do
      create(:item, name: "Groceries", category: category)
      create(:item, name: "Dining Out", category: category)
      visit category_items_path(category, field: "name", q: "Groceries")

      expect(page).to have_content("Groceries")
      expect(page).not_to have_content("Dining Out")
    end
  end

  describe "navigation", :aggregate_failures do
    let!(:item) { create(:item, name: "Groceries", category: category) }

    before { visit category_items_path(category) }

    it "navigates to new item form" do
      click_link "New Item"

      expect(page).to have_current_path(new_category_item_path(category))
    end

    it "navigates to edit item" do
      within("table") { click_link "Edit" }

      expect(page).to have_current_path(edit_item_path(item))
    end

    it "navigates to merge page" do
      within("table") { click_link "Merge" }

      expect(page).to have_content("Merge into Groceries")
    end
  end
end
