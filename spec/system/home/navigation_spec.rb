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

  # The negative half of each rename. Capybara.exact is unset in this project, so link
  # text matches by substring: have_link("Pools") passes just as happily against
  # "Savings Pools", and the positive assertions alone would survive a full revert.
  it "replaces the old entries rather than adding to them", :aggregate_failures do
    visit root_path

    expect(page).to have_link("Home", href: root_path)
    expect(page).to have_no_link("Dashboard")
    expect(page).to have_link("Pools", href: pools_path)
    expect(page).to have_no_link("Savings Pools")
    expect(page).to have_no_link("Statistics")
  end
end
