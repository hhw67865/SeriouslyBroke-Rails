# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Budget income" do
  let(:user) { create(:user, :biweekly) }
  let!(:salary) { create(:category, :income, user: user, name: "Salary") }
  let!(:bonus) { create(:category, :income, :irregular, user: user, name: "Bonus") }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
  end

  it "saves the period and the income categories in one PATCH", :aggregate_failures do
    patch_income(cadence: "weekly", anchor: "2026-09-04", regular_ids: [salary.id])

    expect(response).to redirect_to(budget_page_path)
    expect(user.reload).to be_period_weekly
    expect(salary.reload).to be_regular
    expect(bonus.reload).not_to be_regular
  end

  it "offers scaling when the cadence changes and per-period rules exist", :aggregate_failures do
    create(:rule, :rate, category: create(:category, user: user))

    patch_income(cadence: "monthly", anchor: "2026-09-04")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Before this saves")
  end

  it "scales and saves the categories when the offer is accepted", :aggregate_failures do
    rule = create(:rule, :rate, amount: 100, category: create(:category, user: user))

    patch_income(cadence: "monthly", anchor: "2026-09-04", regular_ids: [salary.id], scale: "1")

    expect(response).to redirect_to(budget_page_path)
    expect(user.reload).to be_period_monthly
    expect(rule.reload.amount).not_to eq(100)
    expect(salary.reload).to be_regular
  end

  it "re-renders 422 on an invalid declaration and leaves regular untouched", :aggregate_failures do
    patch_income(cadence: "weekly", anchor: "", regular_ids: [bonus.id])

    expect(response).to have_http_status(:unprocessable_content)
    expect(salary.reload).to be_regular
    expect(bonus.reload).not_to be_regular
  end

  it "ignores category ids that belong to another user", :aggregate_failures do
    other_category = create(:category, :income, :irregular, user: create(:user), name: "Not mine")

    patch_income(cadence: "weekly", anchor: "2026-09-04", regular_ids: [other_category.id])

    expect(response).to redirect_to(budget_page_path)
    expect(other_category.reload).not_to be_regular
  end

  describe "#preview" do
    # Weekly anchored 2026-09-04 puts Sep 9 in its own period, with Aug 21–27 and Aug 28–Sep 3 the
    # two complete periods behind it — a different grid than the user's saved biweekly one.
    it "computes the figure from the posted cadence and ids, and writes nothing", :aggregate_failures do
      create(:entry, item: create(:item, category: bonus), amount: 500, date: Date.new(2026, 8, 21))
      create(:entry, item: create(:item, category: bonus), amount: 700, date: Date.new(2026, 8, 28))

      travel_to(Date.new(2026, 9, 9)) { post_preview(cadence: "weekly", anchor: "2026-09-04", regular_ids: [bonus.id]) }

      expect(response.body).to include('id="income_measure"', "$600.00")
      expect(user.reload).to be_period_biweekly
      expect(salary.reload).to be_regular
      expect(bonus.reload).not_to be_regular
    end
  end

  private

  def patch_income(cadence:, anchor:, regular_ids: nil, scale: nil)
    params = { user: { period_cadence: cadence, period_anchor_date: anchor } }
    params[:regular_category_ids] = regular_ids if regular_ids
    params[:scale] = scale if scale
    patch budget_income_path, params: params
  end

  def post_preview(cadence:, anchor:, regular_ids:)
    post preview_budget_income_path,
         params: { user: { period_cadence: cadence, period_anchor_date: anchor }, regular_category_ids: regular_ids },
         headers: { "Turbo-Frame" => "income_measure" }
  end
end
