# frozen_string_literal: true

require "rails_helper"

# ** THE SAVINGS STRIP'S CLAIM READER, COSTED (fix wave — LOW-1). **
#
# `#savings_summary` asks a claim of every goal the user owns, and the dashboard renders every one
# of them on one screen. `Category#claim` is the UNBATCHED door — a spending query and an adjustment
# query PER RULE (computed-claims spec §3.3) — so a strip that reached for it would open one set of
# grouped aggregates per goal on the page that lists them all. It reads `ClaimLedger
# #claim_of_category` instead, off ONE ledger built at `#as_of`, and until this file existed nothing
# asserted that: `savings_strip_spec` pins every FIGURE on the strip and would pass just as happily
# against a calculator per row.
#
# ** THE `adjustments` STATEMENTS ARE THE PROBE, on `categories_spec`'s own reasoning. ** A claim is
# read out of two lanes, and the `entries` lane is hopeless here — the dashboard's other panels ask
# their own per-category spending questions, which grow with the row count for reasons this pin does
# not touch. Nothing else on this screen reads `adjustments`, so counting them isolates exactly the
# reader under test: one grouped statement from the ledger, or one per rule from a per-goal
# calculator.
#
# EVERY GOAL CARRIES A RULE, which is not decoration: a claim comes from a rule (§3.3), so a goal
# with none asks the ledger nothing at all and five ruleless goals would cost zero statements — the
# equality would hold trivially and the example would pass against the very thing it forbids.
#
# STRICT EQUALITY AND THE FIGURE NAMED, not "no more than": a bound pins nothing, and a strip that
# stopped reading claims altogether would satisfy a bare equality while printing nobody's money.
RSpec.describe Dashboard::OverviewPresenter do
  # A DECLARED BIWEEKLY PERIOD ANCHORED TODAY, matching `savings_strip_spec`: a user with no cadence
  # falls back to the calendar month and the walk's arithmetic then moves with the day the suite
  # runs on (CLAUDE.md's third flake cause).
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 4_000)
  end
  let(:presenter) { DashboardPresenter.new(user: user, date: Date.current).overview }

  def goal(name, target: 5_000, accrues: 1_000)
    category = create(
      :category, :expense, user: user, name: name, target_amount: target, funded_since: 1.year.ago.to_date
    )
    create(:budget, :per_period_rate, category: category, amount: accrues)
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
    it "asks the same number of times for one goal as for five", :aggregate_failures do
      goal("Vacation")
      one = adjustment_statements

      ["Roof", "Car", "Trip", "Rainy Day"].each { |name| goal(name) }
      five = adjustment_statements

      expect(user.categories.count(&:saving_toward_a_target?)).to eq(5)
      expect(five).to eq(one)
      expect(five).to eq(1)
    end

    # THE REACH DIRECTION, so the count above cannot be one because nothing was read. Five goals,
    # five rows, each carrying the figure §3.2's walk produces: one period at $1,000 against a
    # $5,000 target.
    it "reads every goal's claim off that one statement", :aggregate_failures do
      ["Vacation", "Roof", "Car", "Trip", "Rainy Day"].each { |name| goal(name) }

      expect(presenter.savings_summary.pluck(:balance)).to all(eq(BigDecimal("1000")))
      expect(presenter.total_savings_balance).to eq(BigDecimal("5000"))
    end
  end
end
