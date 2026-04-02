# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items Manage - Merge", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Food", user: user) }
  let!(:target) { create(:item, name: "Groceries", category: category) }
  let!(:source1) { create(:item, name: "Grocery Store", category: category) }
  let!(:source2) { create(:item, name: "Supermarket", category: category) }

  before do
    create_list(:entry, 2, item: target)
    create_list(:entry, 3, item: source1)
    create(:entry, item: source2)
    sign_in user, scope: :user
  end

  describe "merge page", :aggregate_failures do
    before { visit merge_category_items_path(category, target_item_id: target.id) }

    it "shows merge page with target item and other items" do
      expect(page).to have_content("Merge into Groceries")
      expect(page).to have_content("Grocery Store")
      expect(page).to have_content("Supermarket")
      expect(page).not_to have_content_matching_checkbox("Groceries")
    end

    it "merges selected items into target", :aggregate_failures do
      check_item("Grocery Store")
      check_item("Supermarket")
      click_button "Merge Items"

      expect(page).to have_current_path(category_items_path(category))
      expect(page).to have_content("2 item(s) merged into Groceries")
      expect(page).to have_content("Groceries")
      expect(page).not_to have_content("Grocery Store")
      expect(page).not_to have_content("Supermarket")

      expect(target.reload.entries.count).to eq(6)
    end

    it "disables merge button when no items selected" do
      expect(page).to have_button("Merge Items", disabled: true)
    end
  end

  private

  def check_item(name)
    find("label", text: name).find("input[type='checkbox']").check
  end

  def have_content_matching_checkbox(name)
    have_css("label", text: name)
  end
end
