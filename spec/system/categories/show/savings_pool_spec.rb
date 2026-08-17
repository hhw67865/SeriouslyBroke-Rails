# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Savings Pool", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  it "shows savings pool card and navigates to pool details", :aggregate_failures do
    pool = create(:pool, user: user, name: "Main Pool", target_amount: 2000)
    category = create(:category, category_type: "savings", user: user, name: "Emergency Fund", pool: pool)

    visit category_path(category)

    # CHANGED WITH THE ONE NAMER (2d whole-plan review, fix 2). This pinned "Savings Pool", the
    # noun both this page's summary box and its pool card used for a pool the budget block and the
    # entry form's impact card called something else. `Pool::NOUNS` is the single mapping now and
    # a savings pool is a "Goal" everywhere the app speaks about one.
    expect(page).to have_content("Goal")
    expect(page).to have_no_content("Savings Pool")
    expect(page).to have_content("Main Pool")

    click_link "View details"
    expect(page).to have_current_path(pool_path(pool))
  end
end
