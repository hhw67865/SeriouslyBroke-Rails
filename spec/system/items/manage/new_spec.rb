# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items Manage - New", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Food", user: user) }

  before { sign_in user, scope: :user }

  describe "creating an item", :aggregate_failures do
    before { visit new_category_item_path(category) }

    it "shows form with correct elements" do
      expect(page).to have_content("New Item")
      expect(page).to have_content("Food")
      expect(page).to have_field("Item Name")
      expect(page).to have_button("Create Item")
      expect(page).to have_link("Cancel")
    end

    it "creates item with valid data" do
      fill_in "Item Name", with: "Groceries"
      click_button "Create Item"

      expect(page).to have_current_path(category_items_path(category))
      expect(page).to have_content("Groceries was created")
      expect(page).to have_content("Groceries")
    end

    it "shows error for blank name" do
      fill_in "Item Name", with: ""
      click_button "Create Item"

      expect(page).to have_content("can't be blank")
    end

    it "shows error for duplicate name" do
      create(:item, name: "Groceries", category: category)

      fill_in "Item Name", with: "Groceries"
      click_button "Create Item"

      expect(page).to have_content("has already been taken")
    end
  end
end
