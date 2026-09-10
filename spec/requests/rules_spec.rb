# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rules" do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
  end

  it "writes a rule and opens its category on the Budget page", :aggregate_failures do
    post rules_path, params: { rule: { category_id: groceries.id, rule_type: "usage", amount: "400", schedule: "per_period", starts_on: "2026-09-01" } }

    expect(response).to redirect_to(budget_page_path(open: groceries.id))
    expect(groceries.rules.sole).to have_attributes(amount: 400, starts_on: Date.new(2026, 9, 1))
  end

  it "re-renders with the refusal" do
    post rules_path, params: { rule: { category_id: groceries.id, rule_type: "usage", amount: "0", schedule: "per_period" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "previews inside a turbo frame" do
    post preview_rules_path,
         params: { rule: { category_id: groceries.id, rule_type: "bill", amount: "600", schedule: "by_date", anchor_date: "2026-10-15" } },
         headers: { "Turbo-Frame" => "rule_preview" }

    expect(response.body).to include("$600.00")
  end

  # The preview runs a calculator and prints a name, so its owner ids go through current_user like
  # every other door's: a foreign category 404s rather than being priced and named on this page.
  it "never previews another user's category", :aggregate_failures do
    stranger = create(:category, user: create(:user), name: "Theirs")

    post preview_rules_path,
         params: { rule: { category_id: stranger.id, rule_type: "usage", amount: "400", schedule: "per_period" } },
         headers: { "Turbo-Frame" => "rule_preview" }

    expect(response).to have_http_status(:not_found)
    # The card itself, by its own hook: the 404 is raised in `#scoped` before anything is rendered,
    # and asserting on the name would match the debug page's echo of this file rather than the view.
    expect(response.body).not_to include("data-preview")
  end

  it "sends new without a category back to the Budget page" do
    get new_rule_path

    expect(response).to redirect_to(budget_page_path)
  end

  # 404 rather than a raise: this app's test environment rescues, so the refusal is the response.
  it "never edits another user's rule" do
    get edit_rule_path(create(:rule))

    expect(response).to have_http_status(:not_found)
  end
end
