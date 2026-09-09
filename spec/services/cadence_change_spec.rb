# frozen_string_literal: true

require "rails_helper"

RSpec.describe CadenceChange do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let!(:allowance) { create(:rule, :rate, amount: 200, category: groceries) }
  let!(:bill) { create(:rule, :one_off, amount: 500, category: create(:category, user: user)) }

  def change(cadence:, anchor: "2026-09-04") = described_class.new(user: user, declaration: { period_cadence: cadence, period_anchor_date: anchor })

  it "offers scaling when the cadence changes and per-period rules exist", :aggregate_failures do
    offered = change(cadence: "monthly")

    expect(offered).to be_changing
    expect(offered).to be_offered
    expect(offered.lines.map(&:rule)).to eq([allowance])
    expect(offered.lines.first.scaled_amount).to eq(433.33) # 200 × 26 / 12
    expect(change(cadence: "biweekly")).not_to be_offered
  end

  it "applies the declaration and, when asked, the scaling", :aggregate_failures do
    expect(change(cadence: "monthly").apply(scale: true)).to be(true)
    expect(user.reload).to be_period_monthly
    expect(allowance.reload.amount).to eq(433.33)
    expect(bill.reload.amount).to eq(500)
  end

  it "applies the declaration alone when scaling is declined", :aggregate_failures do
    applied = change(cadence: "weekly")

    expect(applied.apply(scale: false)).to be(true)
    expect(applied).not_to be_scaled
    expect(allowance.reload.amount).to eq(200)
  end

  it "saves nothing when the declaration is invalid", :aggregate_failures do
    invalid = change(cadence: "monthly", anchor: "")

    expect(invalid).not_to be_offered
    expect(invalid.apply(scale: true)).to be(false)
    expect(user.reload).to be_period_biweekly
    expect(allowance.reload.amount).to eq(200)
  end
end
