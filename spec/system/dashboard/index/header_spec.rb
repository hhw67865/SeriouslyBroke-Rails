# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Header", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit reports_path
  end

  describe "page header elements", :aggregate_failures do
    it "shows correct title and current month/year" do
      # Scoped to the h1: the sidebar now carries a "Reports" nav link, so a bare
      # have_content("Reports") passes even when the page header says something else.
      expect(page).to have_css("h1", text: "Reports")
      expect(page).to have_content(Date.current.strftime("%B %Y"))
    end
  end
end
