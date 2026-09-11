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
    post adjustments_path, params: { source_type: "Rule", source_id: rule.id, amount: "50" }
    expect(response).to redirect_to(root_path(anchor: "block-#{groceries.id}"))
    expect(rule.adjustments.sole.amount).to eq(50)

    delete adjustment_path(rule.adjustments.sole)
    expect(rule.adjustments.reload).to be_empty
  end

  it "refuses a date outside the period with the reason, back on Home", :aggregate_failures do
    post adjustments_path, params: { source_type: "Rule", source_id: rule.id, amount: "50", date: (user.period_containing(user.today).first - 1).to_s }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("pick a date between")
    expect(response.body).to include("data-tiles")
  end

  # 404 rather than a raise: this app's test environment rescues, so the refusal is the response.
  it "never adjusts another user's rule" do
    post adjustments_path, params: { source_type: "Rule", source_id: create(:rule).id, amount: "50" }

    expect(response).to have_http_status(:not_found)
  end

  it "reduces a savings account and comes back to the savings page", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(user.today).first)

    post adjustments_path, params: { source_type: "Account", source_id: emergency.id, amount: "50", amount_sign: "-1" }

    expect(response).to redirect_to(savings_path)
    expect(emergency.adjustments.sole.amount).to eq(-50)
  end

  it "reduces a savings account and comes back to Home when the form carried return: home", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(user.today).first)

    post adjustments_path, params: { source_type: "Account", source_id: emergency.id, amount: "50", amount_sign: "-1", return: "home" }

    expect(response).to redirect_to(root_path(anchor: "savings-#{emergency.id}"))
    expect(emergency.adjustments.sole.amount).to eq(-50)
  end

  it "refuses an account adjustment with nothing to top up, back on Home", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(user.today).first)

    post adjustments_path, params: { source_type: "Account", source_id: emergency.id, amount: "50", amount_sign: "1", return: "home" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("data-tiles")
  end

  it "refuses an unknown source type" do
    post adjustments_path, params: { source_type: "User", source_id: user.id, amount: "50" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "deletes an account adjustment and returns to Home when the form carried return: home", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(user.today).first)
    change = create(:adjustment, source: emergency, amount: -50, date: user.today)

    delete adjustment_path(change, return: "home")

    expect(response).to redirect_to(root_path(anchor: "savings-#{emergency.id}"))
    expect(emergency.adjustments.reload).to be_empty
  end

  it "never deletes another user's adjustment" do
    other_rule = create(:rule, :rate, amount: 100, starts_on: Date.new(2026, 1, 1))
    another_users_adjustment = create(:adjustment, source: other_rule, amount: 10, date: other_rule.user.today)

    delete adjustment_path(another_users_adjustment)

    expect(response).to have_http_status(:not_found)
  end

  it "deletes an adjustment and returns to Activity when the form carried return: activity", :aggregate_failures do
    post adjustments_path, params: { source_type: "Rule", source_id: rule.id, amount: "50" }
    change = rule.adjustments.sole

    delete adjustment_path(change, return: "activity")

    expect(response).to redirect_to(activity_path)
    expect(rule.adjustments.reload).to be_empty
  end
end
