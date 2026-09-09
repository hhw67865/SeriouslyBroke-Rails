# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Header", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "page header elements", :aggregate_failures do
    it "shows correct title and subtitle for all entries" do
      visit entries_path

      expect(page).to have_content("All Entries")
    end

    it "shows type-specific titles" do
      visit entries_path(type: "expenses")
      expect(page).to have_content("Track and manage your expense transactions")

      visit entries_path(type: "income")
      expect(page).to have_content("Monitor your income sources and earnings")

      # THE SAVINGS HEADER IS GONE (plan 3, task 5) — `SearchHelper#entry_type_config` lost the
      # key, so a stale `?type=savings` link falls back to the "all" header rather than announcing
      # a kind of entry that no longer exists.
      visit entries_path(type: "savings")
      expect(page).to have_content("All Entries")
      expect(page).to have_no_content("Record your savings deposits and contributions")
    end

    it "shows create button" do
      visit entries_path
      expect(page).to have_link("New Entry")
    end
  end

  describe "create button navigation", :aggregate_failures do
    it "navigates to new entry page" do
      visit entries_path
      click_link "New Entry"

      expect(page).to have_current_path(new_entry_path)
      expect(page).to have_content("New Entry")
    end
  end

  describe "search form presence", :aggregate_failures do
    it "shows search form in header" do
      visit entries_path

      expect(page).to have_field("q")
      expect(page).to have_select("field")
    end
  end
end
