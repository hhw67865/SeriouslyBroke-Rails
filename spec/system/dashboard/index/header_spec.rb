# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Header", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit root_path
  end

  describe "page header elements", :aggregate_failures do
    it "shows correct title and current month/year" do
      expect(page).to have_content("Dashboard")
      expect(page).to have_content(Date.current.strftime("%B %Y"))
    end
  end
end
