# frozen_string_literal: true

require "rails_helper"

# THE SHARED READER'S OWN SPEC. These examples lived under `HomePresenter#changed_after_distributing?`
# until the Budget page needed the same answer and the query moved here — and they moved with it,
# because a shared reader whose contract is pinned inside one consumer's spec file is the structural
# version of the defect the extraction closed.
#
# CONVERTED WITH THE READER (two-ledger Task 4). The clock now dates a distribution by
# `Allocation.distributed`, which has no account on it — so `account_ids:`'s per-account map
# collapses to ONE timestamp per user per period, and the question is asked of a CATEGORY.
#
# TWO ARMS, TWO GROUPS. The pool-era arm at the bottom is a transitional surface with a named
# deleter: HomePresenter, BudgetPagePresenter and CategoryBudgetPresenter still pass accounts and
# still ask about pools until Tasks 5 and 6. Its examples are kept rather than deleted precisely
# because those three screens are live, and they go when the keyword does.
#
# WHAT COULD NOT COME ACROSS: "is false for a pool no account can reach". Its whole mechanism was the
# missing key in a per-ACCOUNT map, and there is no per-category map to be missing from — one root,
# one moment. Its replacement is better isolated rather than weaker: "does not read another user's
# split", which is what the owner filter now carries alone.
RSpec.describe DistributionClock do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  # SPEC §8'S ROUGH EDGE. Rule changes apply immediately, so raising a rule the day after a
  # distribution flips its category from `on track` to `behind` with no money having moved. The row
  # says which of the two kinds of `behind` it is, and this is the signal behind the wording.
  #
  # `travel_to` throughout, because the whole reader is a comparison of two timestamps: without a
  # controlled clock the rule and the allocation are written milliseconds apart and every example
  # here would be a coin toss.
  let(:distributed_on) { Time.zone.local(2026, 2, 6, 9, 0, 0) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }

  def raise_rule(rule, to:, at:)
    travel_to(at) { rule.update!(amount: to) }
  end

  # Every SQL statement a block issued, schema and transaction chatter excluded — the suite's own
  # idiom, shared by pool_balance_ledger_spec and ledger_sharing_spec.
  def count_statements(&block)
    statements = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    statements
  end

  describe "over the purpose ledger" do
    # THE CLOCK AS ITS CONVERTED CONSUMERS BUILD IT: a user and a day, and no accounts at all.
    # Rebuilt per call rather than memoised in a `let`, because the timestamp is memoised and every
    # example here writes allocations after the fixture is planted.
    def clock = described_class.new(user: user, today: today)

    def rent_category
      @rent_category ||= create(:category, :expense, :funded, user: user, name: "Rent", priority: 1)
    end

    def rate(category, amount)
      create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
    end

    # An allocation, which is half of what a distribution writes. `date` is the period day the split
    # is FOR; `created_at` is when it was written, and that is the column this reader uses.
    def distribute(amount, at: distributed_on, kind: :allocation, on: today)
      travel_to(at) do
        create(:allocation, kind: kind, to_category: rent_category, amount: amount, date: on)
      end
    end

    it "is true when a rule was raised after this period's distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      distribute(400)
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_category)).to be(true)
    end

    # THE POSITIVE PAIR'S OTHER HALF, on the same shape: same category, same distribution, and the
    # edit on the other side of it. A clause asserted in one direction only is a clause that could be
    # rendering unconditionally.
    it "is false when the rule was last touched before the distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      raise_rule(rule, to: 470, at: distributed_on - 1.hour)
      distribute(470)

      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    it "is false when nothing has been distributed this period" do
      travel_to(distributed_on) { rate(rent_category, 400) }

      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    # A REALLOCATION IS NOT A DISTRIBUTION. `Allocation.distributed` is allocations and sweeps; a
    # `transfer` is the reallocation screen moving money by hand, and it hands nothing out. Written
    # with the same shape and the same clock as the positive example, so only the `kind` differs.
    it "is false when the only allocation this period is a transfer" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      distribute(400, kind: :transfer)
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    # LAST PERIOD'S DISTRIBUTION IS NOT THIS ONE'S. The clause explains a flip that happened since the
    # money was handed out; a split from a fortnight ago says nothing about it, and reading it would
    # mark every rule edited since as "raised after distributing" forever.
    #
    # `on:` puts the split in the PREVIOUS biweekly period (the user is anchored to Feb 6, so this
    # period opens that day and the one before it ran Jan 23 – Feb 5). Both the `date` and the
    # `created_at` fall outside; it is the `date` bound that excludes it, which is the bound
    # AllocationCommitter uses to find the split it replaces.
    it "is false when the only distribution belongs to an earlier period" do
      rule = travel_to(distributed_on - 20.days) { rate(rent_category, 400) }
      distribute(400, at: distributed_on - 18.days, on: today - 14.days)
      raise_rule(rule, to: 470, at: distributed_on - 17.days)

      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    # A SWEEP DATES A DISTRIBUTION TOO. A period whose split is pure sweep — every category closed and
    # nothing re-funded — writes no allocation at all, and reading `to_category_id` alone would miss
    # it entirely: a sweep names only its SOURCE.
    it "counts a sweep as this period's distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      travel_to(distributed_on) do
        create(:allocation, kind: :sweep, from_category: rent_category, amount: 50, date: today)
      end
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_category)).to be(true)
    end

    # ANOTHER USER'S SPLIT DATES NOTHING HERE. The per-account filter that used to carry ownership is
    # gone with the second root, so the owner test on both sides is the only thing left standing
    # between one user's clock and another user's rows — and a clock that read every allocation in the
    # period would tell this user they changed a rule after a distribution they never made.
    it "does not read another user's split as this user's distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Theirs")
      travel_to(distributed_on) do
        create(:allocation, kind: :allocation, to_category: stranger, amount: 400, date: today)
      end
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    # THE TOUCH CASCADE, MEASURED RATHER THAN REASONED ABOUT. `touch: true` is everywhere on this
    # schema — `Allocation belongs_to :from_category/:to_category, touch: true`, and a category
    # touches its user — and if any of it reached `budgets` this clause would fire on every user who
    # distributed and changed nothing. It does not: `Budget belongs_to :category, touch: true` points
    # the other way, and no association anywhere declares `belongs_to :budget, touch: true`.
    #
    # Asserted on the COLUMN and then on the reader, because the second alone would pass if the
    # comparison were broken in the same direction as the cascade.
    it "is not moved by the distribution's own touch cascade", :aggregate_failures do
      rule = travel_to(distributed_on - 1.day) { rate(rent_category, 400) }
      before_at = rule.reload.updated_at

      distribute(400)

      expect(rule.reload.updated_at).to eq(before_at)
      expect(rent_category.reload.updated_at).to be > before_at
      expect(clock.changed_after_distributing?(rent_category)).to be(false)
    end

    # ONE QUERY FOR THE WHOLE SCREEN, which is the reason this class exists at all rather than a
    # method on each presenter: the timestamp is asked once and every row after the first is free.
    # Asserted by counting statements, because the RESULT is the same either way.
    it "asks the database once however many categories are asked about", :aggregate_failures do
      categories = two_loaded_categories
      subject = clock
      answers = nil

      statements = count_statements { answers = categories.map { |c| subject.changed_after_distributing?(c) } }

      expect(answers).to eq([false, false])
      expect(statements).to eq(1)
    end

    # `budgets.load` on both, because the count above is about THIS class's own query and the callers
    # all eager-load their rules — an unloaded association would add one statement per row and
    # measure the fixture rather than the reader. Built OUTSIDE the measured window for the same
    # reason: a fixture created inside it is 24 statements of its own.
    def two_loaded_categories
      rate(rent_category, 400)
      food = create(:category, :expense, :funded, user: user, name: "Food")
      create(:budget, :per_period_rate, pool: nil, category: food, amount: 100)

      [rent_category, food].each { |category| category.budgets.load }
    end
  end

  # ── THE POOL-ERA ARM, kept alive for the three screens that have not converted yet. DELETED BY
  # TASKS 5 AND 6, in the commit that takes `account_ids:` off the last caller. Nothing below changed
  # with the cutover.
  describe "over the pool ledger, until Tasks 5 and 6 move its callers" do
    def clock = described_class.new(user: user, account_ids: user.pools.accounts.ids, today: today)

    def rent_envelope
      @rent_envelope ||= create(:pool, :budget_pool, user: user, account: checking, name: "Rent", priority: 1)
    end

    def rate(pool, amount) = create(:pool_budget, :per_period_rate, pool: pool, amount: amount)

    def distribute(amount, at: distributed_on, kind: :allocation, on: today)
      travel_to(at) do
        create(:pool_movement, kind: kind, from_pool: checking, to_pool: rent_envelope, amount: amount, date: on)
      end
    end

    it "is true when a rule was raised after this period's distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
      distribute(400)
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_envelope)).to be(true)
    end

    it "is false when the rule was last touched before the distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
      raise_rule(rule, to: 470, at: distributed_on - 1.hour)
      distribute(470)

      expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
    end

    # A SWEEP DATES A DISTRIBUTION TOO — the branch that reads the movement's OTHER end.
    it "counts a sweep as this period's distribution" do
      rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
      travel_to(distributed_on) do
        create(:pool_movement, kind: :sweep, from_pool: rent_envelope, to_pool: checking, amount: 50, date: today)
      end
      raise_rule(rule, to: 470, at: distributed_on + 2.hours)

      expect(clock.changed_after_distributing?(rent_envelope)).to be(true)
    end

    # A pool with no account has no distribution to be after — nothing can fund it at all — and a
    # missing key must read as "no distribution" rather than raise.
    it "is false for a pool no account can reach" do
      orphan = create(:pool, user: user, name: "Retirement Supplement", target_amount: 5_000, priority: 1)
      travel_to(distributed_on) { create(:pool_budget, :per_period_rate, pool: orphan, amount: 150) }
      distribute(400)

      expect(clock.changed_after_distributing?(orphan)).to be(false)
    end

    # THE EMPTY SET COSTS NO QUERY, and it is also what tells the two arms apart: `account_ids: []` is
    # a real pool-era question about a user with no accounts, while omitting the keyword is a caller
    # that has stopped asking about accounts at all. Asserted by counting statements, because the
    # RESULT is the same either way.
    it "asks the database nothing when there are no accounts", :aggregate_failures do
      rate(rent_envelope, 400)
      statements = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end

      empty = described_class.new(user: user, account_ids: [], today: today)

      expect(empty.changed_after_distributing?(rent_envelope)).to be(false)
      expect(statements).to eq(0)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end
