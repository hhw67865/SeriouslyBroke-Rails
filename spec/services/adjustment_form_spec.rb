# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdjustmentForm do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:rate) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }
  let(:bread) { create(:item, category: groceries) }
  let(:dated) { create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, item: bread, starts_on: Date.new(2026, 8, 1)) }

  def form(rule, params) = described_class.new(source: rule, params: params, name: "Groceries", today: today)

  it "tops up, reduces, and dates today by default", :aggregate_failures do
    up = form(rate, { amount: "50" })
    expect(up.save).to be(true)
    expect(up.adjustment).to have_attributes(amount: 50, date: today)

    down = form(rate, { amount: "20", amount_sign: "-1", date: "2026-09-05" })
    expect(down.save).to be(true)
    expect(down.adjustment).to have_attributes(amount: -20, date: Date.new(2026, 9, 5))
  end

  it "skips this period by writing minus what accrued", :aggregate_failures do
    skip = form(dated, { skip: "1" })

    expect(skip.skip?).to be(true)
    expect(skip.save).to be(true)
    expect(skip.adjustment.amount).to eq(-100)
  end

  it "refuses a skip with nothing accrued", :aggregate_failures do
    create(:adjustment, source: rate, amount: -400, date: Date.new(2026, 9, 5))
    skip = form(rate, { skip: "1" })

    expect(skip.save).to be(false)
    expect(skip.error_sentence).to eq("Groceries isn't accruing anything this period, so there's nothing to skip.")
  end

  it "refuses a date outside what the rule counts", :aggregate_failures do
    last_period = form(rate, { amount: "10", date: "2026-08-30" })
    expect(last_period.save).to be(false)
    expect(last_period.error_sentence).to eq("Groceries counts this period only, up to today — pick a date between Sep 4 and Sep 9.")

    future = form(dated, { amount: "10", date: "2026-09-20" })
    expect(future.save).to be(false)
    expect(future.error_sentence).to eq("Groceries counts dates from when it started building, up to today — pick a date between Aug 1 and Sep 9.")
  end

  it "refuses a rule that has not started", :aggregate_failures do
    later = create(:rule, :rate, amount: 10, category: create(:category, user: user), starts_on: Date.new(2026, 10, 1))
    attempt = form(later, { amount: "10" })

    expect(attempt.save).to be(false)
    expect(attempt.error_sentence).to eq("Groceries hasn't started counting yet, so there's nothing to adjust.")
  end

  describe "on a savings account" do
    let(:emergency) { create(:account, user: user, name: "Emergency") }

    before do
      create(:account, user: user, name: "Checking")
      create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
    end

    def savings_form(params) = described_class.new(source: emergency, params: params, name: "Emergency", today: today)

    it "reduces and skips, always negative", :aggregate_failures do
      down = savings_form({ amount: "50", amount_sign: "-1" })
      expect(down.save).to be(true)
      expect(down.adjustment).to have_attributes(source: emergency, amount: -50, date: today)

      skip = savings_form({ skip: "1" })
      expect(skip.save).to be(true)
      expect(skip.adjustment.amount).to eq(-150)
    end

    it "refuses a top-up and a date before the first start", :aggregate_failures do
      up = savings_form({ amount: "50", amount_sign: "1" })
      expect(up.save).to be(false)
      expect(up.error_sentence).to eq("Emergency can take more any time — there's nothing to top up.")

      early = savings_form({ amount: "50", amount_sign: "-1", date: "2026-08-01" })
      expect(early.save).to be(false)
      expect(early.error_sentence).to eq("Emergency counts from when its first target started, up to today — pick a date between Aug 21 and Sep 9.")
    end
  end
end
