# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Index - Header", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit pools_path
  end

  describe "page header elements", :aggregate_failures do
    it "shows correct title and subtitle" do
      expect(page).to have_content("Savings Pools")
      # This page lists savings pools and nothing else, so the subtitle has to say where the
      # other two kinds of pool are — otherwise a user who just made an envelope here looks
      # for it on the page they made it from and does not find it.
      expect(page).to have_content("Accounts and budget envelopes live on Home")
    end

    it "shows create button" do
      expect(page).to have_link("New Pool")
    end
  end

  describe "search form presence", :aggregate_failures do
    before do
      create(:pool, user: user, name: "Emergency Fund")
      visit pools_path
    end

    it "shows search field and field selector" do
      expect(page).to have_field("q")
      expect(page).to have_select("field")
    end
  end

  describe "create button navigation", :aggregate_failures do
    it "navigates to new savings pool page" do
      click_link "New Pool"

      expect(page).to have_current_path(new_pool_path)
      expect(page).to have_content("New Pool")
    end
  end
end
