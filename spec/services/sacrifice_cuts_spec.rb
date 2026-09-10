# frozen_string_literal: true

require "rails_helper"

RSpec.describe SacrificeCuts do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  def rule_on(name, *traits, **attributes)
    create(:rule, *traits, category: create(:category, user: user, name: name), starts_on: Date.new(2026, 1, 1), **attributes)
  end

  def cuts_for(map) = described_class.new(user, cuts: map, today: today)

  it "writes the typed amount straight onto a per-period rule", :aggregate_failures do
    rule = rule_on("Groceries", :rate, amount: 800)

    service = cuts_for(rule.id => "700")

    expect(service.apply).to be(true)
    expect(service.count).to eq(1)
    expect(rule.reload.amount).to eq(700)
  end

  it "scales a one-off's target so its per-period claim becomes what was typed", :aggregate_failures do
    rule = rule_on("Vacation", :one_off, amount: 1_200, anchor_date: Date.new(2026, 12, 1))
    claim = rule.steady_ask(today: today)
    typed = (claim - 10).to_s("F")

    service = cuts_for(rule.id => typed)

    expect(service.apply).to be(true)
    expect(rule.reload.steady_ask(today: today)).to be_within(0.01).of(claim - 10)
  end

  it "refuses a fixed rolling bill", :aggregate_failures do
    rule = rule_on("Insurance", :rolling, amount: 600, anchor_date: Date.new(2026, 10, 1), interval_months: 6)

    service = cuts_for(rule.id => "10")

    expect(service.apply).to be(false)
    expect(service.errors).not_to be_empty
    expect(rule.reload.amount).to eq(600)
  end

  it "refuses zero, negative and non-numeric amounts", :aggregate_failures do
    rule = rule_on("Groceries", :rate, amount: 800)

    ["0", "-5", "abc"].each do |typed|
      service = cuts_for(rule.id => typed)

      expect(service.apply).to be(false)
      expect(service.errors).not_to be_empty
    end
    expect(rule.reload.amount).to eq(800)
  end

  it "refuses an amount at or above the rule's current claim", :aggregate_failures do
    rule = rule_on("Groceries", :rate, amount: 800)

    service = cuts_for(rule.id => "800")

    expect(service.apply).to be(false)
    expect(rule.reload.amount).to eq(800)
  end

  it "404s on a rule that belongs to another user" do
    stranger_rule = create(:rule)

    expect { cuts_for(stranger_rule.id => "10").apply }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "writes nothing when one of several cuts is refused", :aggregate_failures do
    groceries = rule_on("Groceries", :rate, amount: 800)
    insurance = rule_on("Insurance", :rolling, amount: 600, anchor_date: Date.new(2026, 10, 1), interval_months: 6)

    service = cuts_for(groceries.id => "700", insurance.id => "10")

    expect(service.apply).to be(false)
    expect(groceries.reload.amount).to eq(800)
    expect(insurance.reload.amount).to eq(600)
  end
end
