# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Savings Pool", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  it "shows savings pool card and navigates to pool details", :aggregate_failures do
    pool = create(:pool, user: user, name: "Main Pool", target_amount: 2000)
    category = create(:category, category_type: "savings", user: user, name: "Emergency Fund", pool: pool)

    visit category_path(category)

    expect(page).to have_content("Savings Pool")
    expect(page).to have_content("Main Pool")

    click_link "View details"
    expect(page).to have_current_path(pool_path(pool))
  end
end
