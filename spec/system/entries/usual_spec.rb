# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries New Usual", type: :system do
  let(:user) { create(:user) }
  let!(:category) { create(:category, user: user, name: "Food") }

  before { sign_in user, scope: :user }

  describe "the strip", :aggregate_failures do
    it "lists items ranked by count then recency, with each one's last amount" do
      frequent = create(:item, category: category, name: "Coffee")
      recent = create(:item, category: category, name: "Tea")
      create_list(:entry, 2, item: frequent, date: Date.current - 10)
      create(:entry, item: recent, date: Date.current - 1, amount: 4.5)

      visit new_entry_path

      expect(page).to have_content("Usual")
      expect(all("[data-usual-item]").pluck("data-usual-item")).to eq(["Coffee", "Tea"])
      expect(page).to have_css("[data-usual-item='Tea']", text: "$4.50")
    end

    it "leaves out an item with nothing entered in the last 90 days" do
      stale = create(:item, category: category, name: "Stale")
      create(:entry, item: stale, date: Date.current - 100)

      visit new_entry_path

      expect(page).to have_no_content("Usual")
    end

    it "is absent for a user with no entries" do
      visit new_entry_path

      expect(page).to have_no_content("Usual")
    end
  end

  describe "tapping a chip", :aggregate_failures do
    it "fills the category, item, amount and description, and shows the last-time hint" do
      item = create(:item, category: category, name: "Coffee")
      create(:entry, item: item, date: Date.current - 1, amount: 18.99, description: "Morning coffee")

      visit new_entry_path
      click_link "Coffee"

      expect(page).to have_select("category_id", selected: "Food")
      expect(page).to have_select("entry_item_id", selected: "Coffee")
      expect(page).to have_field("Amount", with: "18.99")
      expect(page).to have_field("Description", with: "Morning coffee")
      expect(page).to have_css("[data-amount-hint]", text: "Filled from the last time")
    end
  end
end
