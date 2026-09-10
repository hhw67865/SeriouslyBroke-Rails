# frozen_string_literal: true

require "rails_helper"

# The cuts dialled on /sacrifice, written to the rules they came from. Same fixture as
# spec/system/sacrifices/show_spec.rb: a $146.15 gap, closable by the two cuttable rules.
RSpec.describe "Sacrifices" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:fun) { create(:category, user: user, name: "Fun") }
  let!(:groceries_rule) { create(:rule, :rate, category: groceries, amount: 800, starts_on: Date.new(2026, 1, 1)) }
  let!(:fun_rule) { create(:rule, :rate, category: fun, amount: 300, starts_on: Date.new(2026, 1, 1)) }

  around { |example| travel_to(Date.new(2026, 9, 9)) { example.run } }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each do |on|
      create(:entry, item: create(:item, category: salary), amount: 1_000, date: on)
    end
  end

  def patch_cuts(cuts) = patch(sacrifice_path, params: { cuts: cuts })

  it "writes both cuts and lands on Budget once they close the gap", :aggregate_failures do
    patch_cuts(
      groceries_rule.id => "700",
      fun_rule.id => "50"
    )

    expect(response).to redirect_to(budget_page_path)
    expect(flash[:notice]).to eq("Saved — 2 rules cut. Your rules now need $750.00 a period.")
    expect(groceries_rule.reload.amount).to eq(700)
    expect(fun_rule.reload.amount).to eq(50)
  end

  it "writes a cut too small to close the gap and lands back on Sacrifice", :aggregate_failures do
    patch_cuts(groceries_rule.id => "750")

    expect(response).to redirect_to(sacrifice_path)
    expect(flash[:notice]).to eq("Saved — 1 rule cut. Still $50.00 underwater a period.")
    expect(groceries_rule.reload.amount).to eq(750)
  end

  it "refuses a figure above the claim, and writes nothing", :aggregate_failures do
    patch_cuts(groceries_rule.id => "900")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("below what it asks for now")
    expect(groceries_rule.reload.amount).to eq(800)
  end

  it "leaves a row at its claim alone, and refuses a save with nothing dialled down", :aggregate_failures do
    patch_cuts(groceries_rule.id => "800")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Dial a rule down to cut it first")
    expect(groceries_rule.reload.amount).to eq(800)
  end

  it "keeps what was typed on a refused save", :aggregate_failures do
    patch_cuts(groceries_rule.id => "900")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('value="900"')
  end
end
