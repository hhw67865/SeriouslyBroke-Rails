# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items Edit - Form", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Groceries", user: user) }
  let!(:item) { create(:item, name: "Original Item", description: "Original description", frequency: "one_time", category: category) }

  before { sign_in user }

  describe "form display", :aggregate_failures do
    before { visit edit_item_path(item) }

    it "shows all form elements and page content" do
      expect(page).to have_content("Edit Item")
      expect(page).to have_content("Update details for Original Item")
      expect(page).to have_field("Name")
      expect(page).to have_field("Description")
      expect(page).to have_field("Frequency")
      expect(page).to have_button("Update Item")
    end

    it "shows frequency options" do
      expect(page).to have_select("Frequency", options: ["", "One time", "Monthly", "Yearly"])
    end

    it "shows read-only category information" do
      expect(page).to have_content("Category")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Category cannot be changed after creation")
    end

    it "shows navigation elements" do
      expect(page).to have_link("Cancel")
    end

    it "shows breadcrumb navigation" do
      expect(page).to have_link("Categories")
      expect(page).to have_link("Groceries")
      expect(page).to have_content("Edit Original Item")
    end
  end

  describe "form pre-population", :aggregate_failures do
    it "pre-fills form with existing item data" do
      visit edit_item_path(item)

      expect(page).to have_field("Name", with: "Original Item")
      expect(page).to have_field("Description", with: "Original description")
      expect(page).to have_select("Frequency", selected: "One time")
    end

    it "pre-fills monthly frequency correctly" do
      monthly_item = create(:item, :monthly, name: "Monthly Rent", category: category)
      visit edit_item_path(monthly_item)

      expect(page).to have_field("Name", with: "Monthly Rent")
      expect(page).to have_select("Frequency", selected: "Monthly")
    end

    it "pre-fills yearly frequency correctly" do
      yearly_item = create(:item, :yearly, name: "Annual Insurance", category: category)
      visit edit_item_path(yearly_item)

      expect(page).to have_field("Name", with: "Annual Insurance")
      expect(page).to have_select("Frequency", selected: "Yearly")
    end
  end

  describe "form validation", :aggregate_failures do
    before { visit edit_item_path(item) }

    it "shows error for empty name" do
      fill_in "Name", with: ""
      click_button "Update Item"

      expect(page).to have_content("can't be blank")
      expect(page).to have_current_path(edit_item_path(item))
    end

    it "shows error for duplicate name within same category" do
      create(:item, name: "Duplicate Item", category: category)

      fill_in "Name", with: "Duplicate Item"
      click_button "Update Item"

      expect(page).to have_content("has already been taken")
      expect(page).to have_current_path(edit_item_path(item))
    end

    it "allows same name if unchanged" do
      fill_in "Name", with: "Original Item"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      expect(page).to have_current_path(category_path(category))
    end

    it "allows duplicate names in different categories" do
      other_category = create(:category, name: "Dining", user: user)
      create(:item, name: "Shared Name", category: other_category)

      fill_in "Name", with: "Shared Name"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
    end
  end

  describe "successful updates", :aggregate_failures do
    before { visit edit_item_path(item) }

    it "updates name and persists changes" do
      fill_in "Name", with: "Updated Item Name"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      expect(page).to have_current_path(category_path(category))
      # Item name should appear in the category items list
      # We don't need to check the page content since items might be in a collapsed section

      item.reload
      expect(item.name).to eq("Updated Item Name")
    end

    it "updates description and persists changes" do
      fill_in "Description", with: "Updated description text"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      expect(page).to have_current_path(category_path(category))

      item.reload
      expect(item.description).to eq("Updated description text")
    end

    it "updates frequency and persists changes" do
      select "Monthly", from: "Frequency"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      expect(page).to have_current_path(category_path(category))

      item.reload
      expect(item.frequency).to eq("monthly")
    end

    it "clears description when set to empty" do
      fill_in "Description", with: ""
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")

      item.reload
      expect(item.description).to be_blank
    end

    it "updates multiple fields simultaneously" do
      fill_in "Name", with: "Completely Updated"
      fill_in "Description", with: "New description"
      select "Yearly", from: "Frequency"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      expect(page).to have_current_path(category_path(category))

      item.reload
      expect(item.name).to eq("Completely Updated")
      expect(item.description).to eq("New description")
      expect(item.frequency).to eq("yearly")
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit edit_item_path(item) }

    it "returns to category page when clicking Cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(category_path(category))
    end

    it "navigates via breadcrumbs" do
      # Just click the first Categories link since breadcrumb should be at the top
      first("a", text: "Categories").click
      expect(page).to have_current_path(categories_path)
    end

    it "navigates to category via breadcrumb" do
      click_link "Groceries"
      expect(page).to have_current_path(category_path(category))
    end
  end

  describe "category association behavior", :aggregate_failures do
    it "maintains category association after update" do
      visit edit_item_path(item)
      original_category_id = item.category_id

      fill_in "Name", with: "Updated Name"
      click_button "Update Item"

      item.reload
      expect(item.category_id).to eq(original_category_id)
      expect(item.category.name).to eq("Groceries")
    end

    it "displays correct category for different category types" do
      income_category = create(:category, :income, name: "Salary", user: user)
      income_item = create(:item, name: "Monthly Salary", category: income_category)

      visit edit_item_path(income_item)

      expect(page).to have_content("Salary")
      expect(page).to have_content("Category cannot be changed after creation")
    end
  end

  describe "form behavior with different frequencies", :aggregate_failures do
    it "handles one_time frequency updates correctly" do
      item.update!(frequency: "monthly")
      visit edit_item_path(item)

      select "One time", from: "Frequency"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.frequency).to eq("one_time")
    end

    it "handles monthly frequency updates correctly" do
      visit edit_item_path(item)
      select "Monthly", from: "Frequency"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.frequency).to eq("monthly")
    end

    it "handles yearly frequency updates correctly" do
      visit edit_item_path(item)
      select "Yearly", from: "Frequency"
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.frequency).to eq("yearly")
    end
  end

  describe "edge cases and data persistence", :aggregate_failures do
    it "handles very long names correctly" do
      visit edit_item_path(item)
      long_name = "A" * 255
      fill_in "Name", with: long_name
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.name).to eq(long_name)
    end

    it "handles very long descriptions correctly" do
      visit edit_item_path(item)
      long_description = "This is a very long description. " * 50
      fill_in "Description", with: long_description
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.description).to eq(long_description)
    end

    it "handles special characters in name" do
      visit edit_item_path(item)
      special_name = "Item with $pecial Ch@racters & Symbols!"
      fill_in "Name", with: special_name
      click_button "Update Item"

      expect(page).to have_content("Item was successfully updated")
      item.reload
      expect(item.name).to eq(special_name)
    end
  end
end
