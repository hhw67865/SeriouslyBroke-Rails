# frozen_string_literal: true

require "rails_helper"

# THE RUNWAY — this period as a line, with a mark on every day money is needed. The grid this whole
# file shares is biweekly anchored 2026-02-06, so the period containing Sep 9 is **Sep 4 – Sep 17**:
# fourteen days, with Sep 9 as day 6 and eight days left.
RSpec.describe "Home runway", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 1_000)
    sign_in user, scope: :user
  end

  # A one-time bill due on a named day, saving since Aug 1 — four periods of catch-up, which is what
  # puts its money in place before the day arrives.
  def bill(name, amount:, due:, starts_on: Date.new(2026, 8, 1))
    create(
      :rule,
      :bill,
      amount: amount,
      anchor_date: due,
      starts_on: starts_on,
      category: create(:category, user: user, name: name)
    )
  end

  def envelope(name, rate:)
    create(
      :rule,
      :rate,
      amount: rate,
      category: create(:category, user: user, name: name),
      starts_on: Date.new(2026, 1, 1)
    )
  end

  def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  def read_home = travel_to(today) { visit root_path }

  it "draws the period with today's mark and the days that are left", :aggregate_failures do
    read_home

    expect(page).to have_css("[data-period-progress='43']")
    expect(page).to have_css("[data-period-days-left]", text: "8 days left")
    expect(page).to have_css("[data-today-mark]")
    expect(page).to have_css("[data-period-range]", text: "Sep 4")
    expect(page).to have_css("[data-period-range]", text: "Sep 17")
  end

  # A day money is needed on, with the money there: a green dot, its amount above it and its state
  # in words below — a colour is not a sentence.
  it "marks a day money is needed on and says it is ready", :aggregate_failures do
    rule = bill("Dentist", amount: 300, due: Date.new(2026, 9, 12))

    read_home

    expect(page).to have_css("[data-tick='#{rule.id}'] [data-tick-amount]", text: "$300.00")
    expect(page).to have_css("[data-tick='#{rule.id}'] [data-tick-name]", text: "Dentist · ready", visible: :all)
    expect(page).to have_css("[data-due-total]", text: "$300.00 due before Sep 17")
    expect(page).to have_no_css("[data-short-list]")
  end

  # The other state: the day is inside this period and the money is not all there. The gap is named
  # rather than counted, because "1 rule is short" is a fact the user cannot act on.
  it "names a rule whose money is not there for the day", :aggregate_failures do
    rule = bill("Water", amount: 120, due: Date.new(2026, 9, 16))
    spend(rule.category, 100, on: Date.new(2026, 9, 6))

    read_home

    expect(page).to have_css("[data-tick='#{rule.id}'] [data-tick-name]", text: "Water · $100.00 short", visible: :all)
    expect(page).to have_css("[data-short-list]", text: "Water is $100.00 short")
  end

  # A date past the period's close and a rule with no date at all are both off the rail: the runway
  # is about the days money is needed on before this period ends.
  it "leaves off a date past the close and a rule with no date at all", :aggregate_failures do
    envelope("Groceries", rate: 200)
    later = bill("Insurance", amount: 400, due: Date.new(2026, 10, 5))

    read_home

    expect(page).to have_no_css("[data-tick='#{later.id}']")
    expect(page).to have_css("[data-due-total]", text: "Nothing is due before Sep 17")
  end

  it "says what a day may cost while free is above zero" do
    envelope("Groceries", rate: 400)

    read_home

    expect(page).to have_css("[data-pace-line]", text: "$75.00 a day is fine for the rest of the period")
  end

  it "says what a day must come down by while free is under" do
    envelope("Rent", rate: 1_200)

    read_home

    expect(page).to have_css("[data-pace-line]", text: "Spending $25.00 a day less for the rest of this period lands it at zero")
  end

  # A runway is a picture OF a period, and a calendar month nobody set would be thirty invented days.
  describe "before a period is declared" do
    let(:user) { create(:user) }

    it "draws nothing at all" do
      read_home

      expect(page).to have_no_css("[data-runway]")
    end
  end
end
