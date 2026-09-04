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
# EVERY FUND CARRIES A BUILDING RULE, which is not decoration twice over. A claim comes from a rule
# (§3.3), so a category with none asks the ledger nothing at all and five ruleless ones would cost
# zero statements — the equality would hold trivially and the example would pass against the very
# thing it forbids. And since rules-own-the-budget §5 the rule is also what puts a category on this
# strip at all: `Category#building_rule` is the classifier, so a category with a plain rate rule and
# a figure on its own record is not a fund and has no card.
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

  # THE FIGURE IS ON THE RULE (rules-own-the-budget spec §5): `:capped` is a per-period building rule
  # naming a `target_amount`, which is what `Category#building_rule` finds and what
  # `ClaimCalculator#target` caps the walk at. The CATEGORY's own `target_amount` is deliberately not
  # set — the column is dropped by Task 4 and nothing on this strip reads it.
  def fund(name, target: 5_000, accrues: 1_000)
    category = create(:category, :expense, user: user, name: name, funded_since: 1.year.ago.to_date)
    create(:budget, :capped, category: category, amount: accrues, target_amount: target)
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

      expect(user.categories.count { |category| category.building_rule.present? }).to eq(5)
      expect(five).to eq(one)
      expect(five).to eq(1)
    end

    # THE REACH DIRECTION, so the count above cannot be one because nothing was read. Five funds,
    # five rows, each carrying the figure §3.2's walk produces: one period at $1,000 against a
    # $5,000 target.
    it "reads every fund's claim off that one statement", :aggregate_failures do
      ["Vacation", "Roof", "Car", "Trip", "Rainy Day"].each { |name| fund(name) }

      expect(presenter.savings_summary.pluck(:balance)).to all(eq(BigDecimal("1000")))
      expect(presenter.total_savings_balance).to eq(BigDecimal("5000"))
    end
  end

  # ** WHICH CATEGORIES THE STRIP IS ABOUT (rules-own-the-budget spec §5). ** The classifier moved
  # from `Category#saving_toward_a_target?` — a funding start and a figure on the CATEGORY — to
  # `Category#building_rule`, the item-less rule whose unspent money carries. "Which money is being
  # saved" is answered by the SHAPE, which is what lets an emergency fund with no ceiling onto this
  # strip for the first time.
  describe "#savings_summary — which categories are on it" do
    def category(name)
      create(:category, :expense, user: user, name: name, funded_since: 1.year.ago.to_date)
    end

    # PLANTED, re-derived: a $1,000-a-period building rule on a category funded a year ago, read on
    # its anchor day. `#as_of` is `min(this month's end, user.today)` = today, and the period grid is
    # biweekly anchored today — so the walk visits every fortnight from a year ago through today,
    # 27 of them, and an UNCAPPED rule plans its plain $1,000 in each: 27 × 1,000 = $27,000 with
    # nothing spent. The figure is not what this example is about, so it asserts only that the row
    # is THERE and that its target is nil; the claim arithmetic is `claim_calculator_spec`'s.
    it "lists a fund that names no figure at all", :aggregate_failures do
      create(:budget, :building, category: category("Emergency Fund"), amount: 1_000)

      row = presenter.savings_summary.sole

      expect(row[:name]).to eq("Emergency Fund")
      expect(row[:target_amount]).to be_nil
      expect(row[:progress_percentage]).to eq(0)
    end

    # THE CAPPED HALF, so the example above cannot pass because the strip lists everything.
    it "carries the rule's own target on a capped fund", :aggregate_failures do
      create(:budget, :capped, category: category("Vacation"), amount: 500, target_amount: 5_000)

      row = presenter.savings_summary.sole

      expect(row[:target_amount]).to eq(5_000)
    end

    # ** THE OTHER DIRECTION, AND IT IS THE ONE THE OLD CLASSIFIER GOT WRONG. ** A category with a
    # figure on its own record and a rule whose money RESETS every period is an envelope somebody
    # set a ceiling on — nothing about it builds up, and no claim formula reads that figure. It had
    # a card under `#saving_toward_a_target?`; it has none now.
    it "leaves out a category whose rule resets, whatever the category's own column says" do
      create(:budget, :per_period_rate, category: category("Groceries"), amount: 400)
      user.categories.find_by(name: "Groceries").update!(target_amount: 5_000)

      expect(presenter.savings_summary).to be_empty
    end

    # AN ITEM-BACKED BUILDING RULE IS NOT THE CATEGORY'S OWN LANE (§3.1's partition): money set aside
    # for one item is not the category building up, and `Category#building_rule` reads the item-less
    # rule for exactly that reason.
    it "leaves out a category whose only building rule pays one item" do
      groceries = category("Groceries")
      item = create(:item, category: groceries)
      create(:budget, :building, category: groceries, item: item, amount: 100)

      expect(presenter.savings_summary).to be_empty
    end
  end
end
