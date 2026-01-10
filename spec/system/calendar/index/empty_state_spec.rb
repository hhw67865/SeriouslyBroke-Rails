# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Index - Empty State", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit calendar_path
  end

  describe "when no entries exist", :aggregate_failures do
    it "shows empty state message" do
      expect(page).to have_content("No entries recorded this month")
    end

    it "provides link to add entry" do
      expect(page).to have_link("Add an entry", href: new_entry_path)
    end

    it "navigates to new entry form when clicking add link" do
      click_link "Add an entry"

      expect(page).to have_current_path(new_entry_path)
    end
  end

  describe "when entries exist in current month", :aggregate_failures do
    before do
      category = create(:category, :expense, user: user)
      item = create(:item, category: category)
      create(:entry, item: item, date: Date.current)
      visit calendar_path
    end

    it "does not show empty state message" do
      expect(page).not_to have_content("No entries recorded this month")
    end
  end
end
