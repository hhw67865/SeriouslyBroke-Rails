# frozen_string_literal: true

require "rails_helper"

# The categories page's holdings card, one example per state it can be in. `Capybara.exact` is
# unset and this page is full of chrome that matches substrings, so every assertion is scoped to
# `[data-holdings-card]` and every positive is paired with a negative.
RSpec.describe "Categories Show - Holdings card", type: :system do
  let(:base_date) { Date.current.beginning_of_month }
  let(:user) { create(:user, period_cadence: :monthly, period_anchor_date: Date.current.beginning_of_month) }

  before { sign_in user, scope: :user }

  def card = find("[data-holdings-card]")

  # State 1 — nothing claims the category.
  it "says a category with no rule claims nothing, and points at the Budget page", :aggregate_failures do
    visit category_path(create(:category, :expense, user: user, name: "Health"))

    expect(card["data-holdings-state"]).to eq("unruled")
    within(card) do
      expect(page).to have_content("Unbudgeted")
      expect(page).to have_content("Nothing claims this category's money.")
      expect(page).to have_link("Give it a rule on the Budget page", href: budget_page_path)
      expect(page).to have_no_content("Claimed")
    end
  end

  # State 2 — a rate rule claims it. PLANTED: `max(0, rate + Σ adjustments − spent)` =
  # `max(0, 400 + 0 − 0)` = $400.00, which is the whole of the category's claim.
  def envelope
    create(:category, :expense, user: user, name: "Groceries")
      .tap { |groceries| create(:rule, :rate, category: groceries, amount: 400) }
  end

  # The card offers no editor of its own: what a category claims is decided by its rules, and a
  # rule is written on the Budget page.
  it "names an envelope, prints what it claims and points at the Budget page", :aggregate_failures do
    visit category_path(envelope)

    expect(card["data-holdings-state"]).to eq("ruled")
    expect(find("[data-figure='claim']").text).to eq("$400.00")
    within(card) do
      expect(page).to have_css("h2", exact_text: "Envelope")
      expect(page).to have_link("Rules on the Budget page", href: budget_page_path)
      expect(page).to have_css("[data-holdings-rule='Groceries']").and have_content("1 rule")
      expect(page).to have_no_content("swept").and have_no_content("available")
      expect(page).to have_no_css("[data-holdings-progress]")
    end
  end

  # State 3 — a goal, alone on its category, so the bar has something to be a fraction of.
  # PLANTED: a $2,000 goal due at the close of the fourth month from this one, its walk opening in
  # this period. Four boundaries remain, so `planned = 2,000 ÷ 4` = $500.00, nothing is spent, and
  # the bar is `(500 ÷ 2,000 × 100).round` = 25.
  def goal
    create(:category, :expense, user: user, name: "Vacation").tap do |vacation|
      create(
        :rule,
        :choice,
        category: vacation,
        amount: 2_000,
        interval_months: nil,
        anchor_date: (base_date + 4.months) - 1.day,
        starts_on: base_date
      )
    end
  end

  it "calls a goal a target and draws its built-up against the rule's figure", :aggregate_failures do
    visit category_path(goal)

    within(card) { expect(page).to have_css("h2", exact_text: "Target") }
    expect(card).to have_no_content("Envelope")
    expect(find("[data-figure='claim']").text).to eq("$500.00")
    within("[data-holdings-progress]") do
      expect(page).to have_content("25% complete")
      expect(page).to have_content("Target: $2,000.00")
    end
  end
end
