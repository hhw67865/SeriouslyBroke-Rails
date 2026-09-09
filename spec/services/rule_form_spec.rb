# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuleForm do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def form(params, rule: nil) = described_class.new(user, params, rule: rule)

  it "writes a per-period allowance, starting today unless told otherwise", :aggregate_failures do
    saved = form({ category_id: groceries.id, rule_type: "usage", amount: "400", schedule: "per_period" })

    expect(saved.save).to be(true)
    expect(saved.rule).to have_attributes(anchor_date: nil, interval_months: nil, keeps_unspent: false, amount: 400, starts_on: user.today)
  end

  it "writes a fund when keeps is ticked, and ignores keeps for a dated rule", :aggregate_failures do
    fund = form({ category_id: groceries.id, rule_type: "usage", amount: "60", schedule: "per_period", keeps: "1" })
    dated = form({ category_id: groceries.id, rule_type: "bill", amount: "600", schedule: "by_date", keeps: "1", anchor_date: "2026-10-15", item_id: bread.id })

    expect(fund.save).to be(true)
    expect(fund.rule).to be_keeps_unspent
    expect(dated.save).to be(true)
    expect(dated.rule).to have_attributes(keeps_unspent: false, anchor_date: Date.new(2026, 10, 15), interval_months: nil)
  end

  it "writes an interval only when the rule repeats, and a start date when given", :aggregate_failures do
    rolling = form({ category_id: groceries.id, rule_type: "bill", amount: "180", schedule: "by_date", anchor_date: "2026-10-01", repeats: "1", interval_months: "6", starts_on: "2026-01-01" })

    expect(rolling.save).to be(true)
    expect(rolling.rule).to have_attributes(interval_months: 6, starts_on: Date.new(2026, 1, 1))
  end

  it "refuses incoherent choices before touching the rule", :aggregate_failures do
    no_date = form({ category_id: groceries.id, rule_type: "bill", amount: "1", schedule: "by_date" })
    stray_interval = form({ category_id: groceries.id, rule_type: "bill", amount: "1", schedule: "per_period", interval_months: "3" })
    unknown = form({ category_id: groceries.id, rule_type: "wish", amount: "1", schedule: "weekly" })

    expect([no_date, stray_interval, unknown].map(&:save)).to all(be(false))
    expect(no_date.errors[:schedule]).to include("needs the date it is first due")
    expect(stray_interval.errors[:schedule]).to include("does not take a number of months — tick \"repeats\" to set one")
    expect(unknown.errors[:schedule]).to include("is not one of the choices on this form")
    expect(unknown.errors[:rule_type]).to include("is not a kind of rule")
    expect(Rule.count).to eq(0)
  end

  it "carries the rule's errors onto the form's fields", :aggregate_failures do
    create(:rule, category: groceries)
    second = form({ category_id: groceries.id, rule_type: "usage", amount: "10", schedule: "per_period" })

    expect(second.save).to be(false)
    expect(second.errors[:item_id]).to include(Rule::CATCH_ALL_TAKEN)
    expect(form({ category_id: groceries.id, rule_type: "usage", amount: "0", schedule: "per_period" }).tap(&:save).errors[:amount]).to be_present
  end

  it "reads an existing rule back into words and edits it", :aggregate_failures do
    rule = create(:rule, :rolling, category: groceries, amount: 180, interval_months: 6, anchor_date: Date.new(2026, 10, 1))
    words = described_class.from(rule)

    expect(words).to include(schedule: "by_date", repeats: true, interval_months: 6, anchor_date: Date.new(2026, 10, 1), keeps: false)

    edited = form(words.merge(amount: "200"), rule: rule)
    expect(edited.save).to be(true)
    expect(rule.reload.amount).to eq(200)
    expect(edited).to be_persisted
  end
end
