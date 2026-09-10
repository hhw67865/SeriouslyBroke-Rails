# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adjustments" do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let!(:rule) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
  end

  it "tops up and takes back", :aggregate_failures do
    post adjustments_path, params: { rule_id: rule.id, amount: "50" }
    expect(response).to redirect_to(budget_page_path(open: groceries.id))
    expect(rule.adjustments.sole.amount).to eq(50)

    delete adjustment_path(rule.adjustments.sole)
    expect(rule.adjustments.reload).to be_empty
  end

  it "refuses a date outside the period with the reason", :aggregate_failures do
    post adjustments_path, params: { rule_id: rule.id, amount: "50", date: (user.period_containing(user.today).first - 1).to_s }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("pick a date between")
  end

  # 404 rather than a raise: this app's test environment rescues, so the refusal is the response.
  it "never adjusts another user's rule" do
    post adjustments_path, params: { rule_id: create(:rule).id, amount: "50" }

    expect(response).to have_http_status(:not_found)
  end
end
