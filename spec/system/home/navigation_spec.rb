# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Navigation", type: :system do
  let(:user) { create(:user, :biweekly) }

  before { sign_in user, scope: :user }

  it "lands on Home at the root" do
    visit root_path

    expect(page).to have_css("h1", text: "Home")
  end

  it "keeps the dashboard reachable as Reports", :aggregate_failures do
    visit reports_path

    expect(page).to have_current_path(reports_path)
    expect(page).to have_css("h1", text: "Reports")
  end

  it "lists Reports in the sidebar" do
    visit root_path

    expect(page).to have_link("Reports", href: reports_path)
  end

  it "replaces the old Dashboard entry rather than adding to it", :aggregate_failures do
    visit root_path

    expect(page).to have_link("Home", href: root_path)
    expect(page).to have_no_link("Dashboard")
    expect(page).to have_link("Pools", href: pools_path)
  end
end
