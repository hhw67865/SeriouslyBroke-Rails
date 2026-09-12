# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentPattern do
  let(:today) { Date.new(2026, 9, 9) }

  def pay(days_ago, amount) = [today - days_ago, amount.to_d]

  def pattern(payments, periods_per_year: 12) = described_class.new(payments, today: today, periods_per_year: periods_per_year)

  describe "with no payments" do
    subject(:none) { pattern([]) }

    it "has nothing to say", :aggregate_failures do
      expect(none.count).to eq(0)
      expect(none.last_paid).to be_nil
      expect(none.typical).to be_nil
      expect(none.usually_words).to eq("—")
      expect(none.per_period).to be_nil
    end
  end

  describe "with one payment" do
    subject(:once) { pattern([pay(10, 50)]) }

    it "counts it but infers no cadence", :aggregate_failures do
      expect(once.count).to eq(1)
      expect(once.last_paid).to eq(pay(10, 50))
      expect(once.usually_words).to eq("once so far")
      expect(once.per_period).to be_nil
    end
  end

  describe "cadence buckets, at their boundaries" do
    {
      19 => "several a month",
      20 => "monthly",
      45 => "monthly",
      46 => "every 3 months",
      110 => "every 3 months",
      111 => "every 6 months",
      220 => "every 6 months",
      221 => "every 12 months",
      450 => "every 12 months",
      451 => "now and then"
    }.each do |gap, words|
      it "reads a #{gap}-day gap as #{words.inspect}" do
        expect(pattern([pay(0, 10), pay(gap, 10)]).cadence_words).to eq(words)
      end
    end
  end

  describe "the range rule" do
    it "shows one amount when the last 3 payments sit within 20% of their median", :aggregate_failures do
      even = pattern([pay(0, "20.50"), pay(31, "19.50"), pay(62, "20.00")])

      expect(even.range?).to be(false)
      expect(even.usually_words).to eq("$20.00 monthly")
    end

    it "shows a range when the last 3 payments spread past 20% of their median", :aggregate_failures do
      spread = pattern([pay(0, "44.80"), pay(31, "13.30"), pay(62, "20.00")])

      expect(spread.range?).to be(true)
      expect(spread.low).to eq(13.30)
      expect(spread.high).to eq(44.80)
      expect(spread.usually_words).to eq("$13.30–$44.80 monthly")
    end
  end

  describe "lapsing" do
    it "prefixes 'was' once the gap since the last payment doubles the median gap, and drops A period", :aggregate_failures do
      lapsed = pattern([pay(131, 10), pay(162, 10), pay(192, 10)])

      expect(lapsed.lapsed?).to be(true)
      expect(lapsed.usually_words).to eq("was $10.00 monthly")
      expect(lapsed.per_period).to be_nil
    end

    it "is not lapsed while the gap since the last payment stays within twice the median", :aggregate_failures do
      current = pattern([pay(20, 10), pay(51, 10), pay(81, 10)])

      expect(current.lapsed?).to be(false)
      expect(current.usually_words).to eq("$10.00 monthly")
    end
  end

  describe "stale" do
    it "is stale once lapsed, or once a single payment is over a year old, and never with no payments", :aggregate_failures do
      expect(pattern([pay(131, 10), pay(162, 10), pay(192, 10)]).stale?).to be(true)
      expect(pattern([pay(367, 95), pay(732, 95)]).stale?).to be(false)
      expect(pattern([pay(400, 48)]).stale?).to be(true)
      expect(pattern([pay(300, 48)]).stale?).to be(false)
      expect(pattern([pay(20, 10), pay(51, 10), pay(81, 10)]).stale?).to be(false)
      expect(pattern([]).stale?).to be(false)
    end
  end

  describe "per_period" do
    it "divides a monthly cost by a monthly user's periods", :aggregate_failures do
      monthly = pattern([pay(0, "18.99"), pay(31, "18.99"), pay(61, "18.99"), pay(92, "18.99")], periods_per_year: 12)

      expect(monthly.cadence_words).to eq("monthly")
      expect(monthly.per_period).to eq(18.65)
    end

    it "spreads a yearly cost across a biweekly user's 26 periods", :aggregate_failures do
      yearly = pattern([pay(0, "120.00"), pay(365, "120.00")], periods_per_year: 26)

      expect(yearly.cadence_words).to eq("every 12 months")
      expect(yearly.per_period).to eq(4.62)
    end

    it "caps a several-a-month item on the payments actually seen in the last year", :aggregate_failures do
      often = pattern(Array.new(10) { |i| pay(i * 3, "5.00") }, periods_per_year: 12)

      expect(often.cadence_words).to eq("several a month")
      expect(often.per_period).to eq(4.17)
    end
  end
end
