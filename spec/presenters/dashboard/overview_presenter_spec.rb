# frozen_string_literal: true

require "rails_helper"

# The savings strip's claim reader, costed. `#savings_summary` asks a claim of every goal the user
# owns and the page renders them all at once, so it reads one `ClaimLedger` rather than a
# calculator per row. Nothing else on this screen touches `adjustments`, so counting those
# statements isolates exactly the reader under test.
RSpec.describe Dashboard::OverviewPresenter do
  # A declared biweekly period anchored today, matching savings_strip_spec: a user with no cadence
  # falls back to the calendar month and the walk's arithmetic then moves with the day the suite
  # runs on.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:presenter) { DashboardPresenter.new(user: user, date: Date.current).overview }

  # A fund is a one-off dated rule whose amount is its target. Five biweekly boundaries fall in
  # today through `today + 9.weeks`, so the first period's share is `5,000 ÷ 5`.
  def fund(name, target: 5_000, due: Date.current + 9.weeks)
    category = create(:category, :expense, user: user, name: name)
    create(
      :rule,
      category: category,
      item: nil,
      amount: target,
      starts_on: Date.current,
      anchor_date: due,
      interval_months: nil
    )
    category
  end

  def adjustment_statements
    statements = []
    recorder = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
      DashboardPresenter.new(user: user, date: Date.current).overview.savings_summary
    end
    statements.count { |sql| sql.include?(%("adjustments")) }
  end

  describe "#savings_summary query cost" do
    it "asks the same number of times for one fund as for five", :aggregate_failures do
      fund("Vacation")
      one = adjustment_statements

      ["Roof", "Car", "Trip", "Rainy Day"].each { |name| fund(name) }
      five = adjustment_statements

      expect(Rule.saving_toward_a_date.count).to eq(5)
      expect(five).to eq(one)
      expect(five).to eq(1)
    end

    # The reach direction, so the count above cannot be one because nothing was read: five funds,
    # five rows, each carrying `5,000 ÷ 5` = $1,000.00.
    it "reads every fund's claim off that one statement", :aggregate_failures do
      ["Vacation", "Roof", "Car", "Trip", "Rainy Day"].each { |name| fund(name) }

      expect(presenter.savings_summary.map(&:built_up)).to all(eq(BigDecimal("1000")))
      expect(presenter.total_savings_balance).to eq(BigDecimal("5000"))
    end
  end

  # Which categories the strip is about: an item-less, non-bill rule with an anchor and no
  # interval. "Which money is being saved" is answered by the shape.
  describe "#savings_summary — which categories are on it" do
    def category(name)
      create(:category, :expense, user: user, name: name)
    end

    it "lists a goal and carries its own amount as the target", :aggregate_failures do
      fund("Vacation")

      row = presenter.savings_summary.sole

      expect(row.category.name).to eq("Vacation")
      expect(presenter.savings_target(row)).to eq(5_000)
    end

    # A rule whose money resets is an envelope. Kept because it is the half that stops the example
    # above passing against a strip that lists everything.
    it "leaves out a category whose rule resets" do
      create(:rule, :rate, category: category("Groceries"), amount: 400)

      expect(presenter.savings_summary).to be_empty
    end

    # A rule that repeats is a recurring bill: the water rates every six months accrue exactly as a
    # goal does and are not savings.
    it "leaves out a category whose only dated rule repeats" do
      create(
        :rule,
        category: category("Water"),
        item: nil,
        amount: 600,
        starts_on: Date.current,
        anchor_date: Date.current + 9.weeks,
        interval_months: 6
      )

      expect(presenter.savings_summary).to be_empty
    end

    def one_off(name, type, amount)
      create(
        :rule,
        type,
        category: category(name),
        item: nil,
        amount: amount,
        starts_on: Date.current,
        anchor_date: Date.current + 9.weeks,
        interval_months: nil
      )
    end

    # A one-off the user typed `bill` has the same four columns as a goal and accrues by the same
    # walk, so only the word the user chose can tell them apart. The pair is planted, so the
    # absence is a fact about the type rather than about the fixture.
    it "leaves out a one-off bill while listing the goal beside it", :aggregate_failures do
      one_off("Tax Estimate", :bill, 3_000)
      goal = one_off("Vacation", :choice, 5_000)

      expect(presenter.savings_summary.map { |row| row.category.name }).to eq(["Vacation"])
      expect(presenter.savings_target(presenter.savings_summary.sole)).to eq(goal.amount)
    end

    # A goal that has been spent is `paid`, and its built-up is $0.00 by construction — the payment
    # emptied the fund. Without `#paid?` the row would take the "barely started" arm.
    it "reads a spent goal as paid rather than as barely started", :aggregate_failures do
      vacation = fund("Vacation")
      create(:entry, item: create(:item, category: vacation), amount: 5_000, date: Date.current)

      row = presenter.savings_summary.sole

      expect(row).to be_paid
      expect(row.paid_on).to eq(Date.current)
      expect(row.built_up).to eq(0)
      expect(row.target).to eq(5_000)
    end

    # The other direction, and it is the one that says why `paid` had to be a reader of its own: a
    # fund at $0.00 is not a fund paid.
    it "leaves a goal one dollar short unpaid, at the same $0.00", :aggregate_failures do
      vacation = fund("Vacation")
      create(:entry, item: create(:item, category: vacation), amount: 4_999, date: Date.current)

      row = presenter.savings_summary.sole

      expect(row).not_to be_paid
      expect(row.paid_on).to be_nil
      expect(row.built_up).to eq(0)
    end

    # An item-backed rule is not the category's own lane: money saved for one item is not the
    # category saving.
    it "leaves out a category whose only goal pays one item" do
      groceries = category("Groceries")
      item = create(:item, category: groceries)
      create(:rule, :by_date, category: groceries, item: item, amount: 100)

      expect(presenter.savings_summary).to be_empty
    end
  end

  # A fund with a sibling rule: the row is the fund's, not the category's. The fund is item-less,
  # $2,400 due `today + 7.weeks` — four boundaries, so `2,400 ÷ 4` = $600. The bill is on the item
  # "Insurance", $600 due three days out, inside this period, so the catch-up asks the whole $600.
  # Read as the category's, the row would say `$1,200.00 of $2,400.00`: half full over a fund a
  # quarter full.
  describe "#savings_summary — a fund that is not the whole category", :aggregate_failures do
    def car_fund
      car = create(:category, :expense, user: user, name: "Car")
      create(
        :rule,
        category: car,
        item: nil,
        amount: 2_400,
        starts_on: Date.current,
        anchor_date: Date.current + 7.weeks,
        interval_months: nil
      )
      car
    end

    def insurance_bill_on(car)
      create(
        :rule,
        category: car,
        item: create(:item, category: car, name: "Insurance"),
        amount: 600,
        starts_on: Date.current,
        anchor_date: Date.current + 3.days,
        interval_months: nil
      )
    end

    it "carries the fund's own built-up and no target" do
      insurance_bill_on(car_fund)

      row = presenter.savings_summary.sole

      expect(row.built_up).to eq(BigDecimal("600"))
      expect(presenter.savings_target(row)).to be_nil
      expect(presenter.savings_progress(row)).to eq(0)
      expect(presenter.total_savings_balance).to eq(BigDecimal("600"))
    end

    # The other direction on the same fixture minus the sibling: the ceiling comes back the moment
    # the fund is the whole category, and `(600 ÷ 2,400 × 100).round` = 25.
    it "carries the target once the fund is the whole category" do
      car_fund

      row = presenter.savings_summary.sole

      expect(row.built_up).to eq(BigDecimal("600"))
      expect(presenter.savings_target(row)).to eq(2_400)
      expect(presenter.savings_progress(row)).to eq(25)
      expect(presenter.total_savings_balance).to eq(BigDecimal("600"))
    end
  end
end
