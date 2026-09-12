# frozen_string_literal: true

require "rails_helper"

# Home is the signed-in root, and the sidebar's own entry points at it. Everything else about the
# sidebar is `spec/system/navbar_spec.rb`'s.
RSpec.describe "Home navigation", type: :system do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 100)
    sign_in user, scope: :user
  end

  # Home's own heading is the day, not the word "Home" — that headline belongs to the sidebar link.
  it "lands on Home at the root", :aggregate_failures do
    visit root_path

    expect(page).to have_css("[data-tiles] [data-tile='free']")
    expect(page).to have_link("Home", href: root_path)
  end
end
