# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Navigation", type: :system do
  let(:user) { create(:user, :biweekly) }

  before { sign_in user, scope: :user }

  it "lands on Home at the root" do
    visit root_path

    expect(page).to have_css("h1", text: "Home")
  end

  # The task brief expected an h1 of "Reports" here, while the same brief requires every
  # dashboard view to stay exactly as it is — and spec/system/dashboard/index/header_spec.rb
  # still asserts the "Dashboard" heading. This task relocates the route; renaming the
  # page's copy is a separate decision, so the assertion follows the shipped page.
  it "keeps the dashboard reachable as Reports", :aggregate_failures do
    visit reports_path

    expect(page).to have_current_path(reports_path)
    expect(page).to have_css("h1", text: "Dashboard")
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
