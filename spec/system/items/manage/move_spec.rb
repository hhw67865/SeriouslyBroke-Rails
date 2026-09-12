# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items Manage - Move", type: :system do
  let!(:user) { create(:user) }
  let!(:source_category) { create(:category, name: "Food", user: user) }
  let!(:target_category) { create(:category, name: "Dining", user: user) }
  let!(:pizza) { create(:item, name: "Pizza", category: source_category) }
  let!(:sushi) { create(:item, name: "Sushi", category: source_category) }

  before do
    create(:entry, item: pizza)
    create(:entry, item: sushi)
    sign_in user, scope: :user
  end

  describe "moving items", :aggregate_failures do
    before { visit category_items_path(source_category) }

    it "moves selected items to another category" do
      check_item("Pizza")
      select "Dining", from: "target_category_id"
      click_button "Move"

      expect(page).to have_content("Items moved to Dining")
      expect(page).not_to have_content("Pizza")
      expect(page).to have_content("Sushi")

      expect(pizza.reload.category).to eq(target_category)
    end

    it "moves everything selected under one flash", :aggregate_failures do
      check_item("Pizza")
      check_item("Sushi")
      select "Dining", from: "target_category_id"
      click_button "Move"

      expect(page).to have_text("Items moved to Dining", count: 1)
      expect(pizza.reload.category).to eq(target_category)
      expect(sushi.reload.category).to eq(target_category)
    end

    it "auto-merges when target has item with same name" do
      create(:item, name: "Pizza", category: target_category)

      check_item("Pizza")
      select "Dining", from: "target_category_id"
      click_button "Move"

      expect(page).to have_content("Items moved to Dining")
      expect(target_category.items.where(name: "Pizza").count).to eq(1)
      expect(target_category.items.find_by(name: "Pizza").entries.count).to eq(1)
    end

    it "refuses the whole move when an item's rule would meet another rule", :aggregate_failures do
      twin = create(:item, name: "Pizza", category: target_category)
      [pizza, twin].each { |item| create(:rule, category: item.category, item: item) }

      check_item("Pizza")
      check_item("Sushi")
      select "Dining", from: "target_category_id"
      click_button "Move"

      expect(page).to have_content("Pizza #{Item::RULE_ALREADY_THERE}")
      expect(page).to have_no_content("Items moved to Dining")
      expect(pizza.reload.category).to eq(source_category)
      expect(sushi.reload.category).to eq(source_category)
    end

    it "shows alert when no items selected" do
      select "Dining", from: "target_category_id"
      click_button "Move"

      expect(page).to have_content("No items selected")
    end
  end

  private

  def check_item(name)
    row = find("tr", text: name)
    row.find("input[type='checkbox']").check
  end
end
