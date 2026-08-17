# frozen_string_literal: true

require "rails_helper"

# THE SHARED READER'S OWN SPEC. These examples lived under `HomePresenter#changed_after_distributing?`
# until the Budget page needed the same answer and the query moved here — and they moved with it,
# because a shared reader whose contract is pinned inside one consumer's spec file is the structural
# version of the defect the extraction closed. `HomePresenter` now delegates; two of the branches
# below (the pure-sweep fold and the previous-period `date` bound) are reachable through no screen's
# spec at all.

RSpec.describe DistributionClock do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  # SPEC §8'S ROUGH EDGE. Rule changes apply immediately, so raising a rule the day after a
  # distribution flips its envelope from `on track` to `behind` with no money having moved. The
  # row says which of the two kinds of `behind` it is, and this is the signal behind the wording.
  #
  # `travel_to` throughout, because the whole reader is a comparison of two timestamps: without a
  # controlled clock the rule and the movement are written milliseconds apart and every example
  # here would be a coin toss.
  let(:distributed_on) { Time.zone.local(2026, 2, 6, 9, 0, 0) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }

  # THE CLOCK AS ITS TWO CONSUMERS BUILD IT: over the accounts the screen has already loaded.
  # Rebuilt per call rather than memoised in a `let`, because `#latest` memoises its query and
  # every example here writes movements after the fixture is planted.
  def clock = DistributionClock.new(user: user, account_ids: user.pools.accounts.ids, today: today)

  def envelope(name, priority:)
    create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
  end

  def rate(pool, amount) = create(:pool_budget, :per_period_rate, pool: pool, amount: amount)

  def rent_envelope = @rent_envelope ||= envelope("Rent", priority: 1)

  # An allocation, which is half of what a distribution writes. `date` is the period day the
  # split is FOR; `created_at` is when it was written, and that is the column this reader uses.
  def distribute(amount, at: distributed_on, kind: :allocation, on: today)
    travel_to(at) do
      create(:pool_movement, kind: kind, from_pool: checking, to_pool: rent_envelope, amount: amount, date: on)
    end
  end

  def raise_rule(rule, to:, at:)
    travel_to(at) { rule.update!(amount: to) }
  end

  it "is true when a rule was raised after this period's distribution" do
    rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
    distribute(400)
    raise_rule(rule, to: 470, at: distributed_on + 2.hours)

    expect(clock.changed_after_distributing?(rent_envelope)).to be(true)
  end

  # THE POSITIVE PAIR'S OTHER HALF, on the same shape: same envelope, same distribution, and the
  # edit on the other side of it. A clause asserted in one direction only is a clause that could
  # be rendering unconditionally.
  it "is false when the rule was last touched before the distribution" do
    rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
    raise_rule(rule, to: 470, at: distributed_on - 1.hour)
    distribute(470)

    expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
  end

  it "is false when nothing has been distributed this period" do
    travel_to(distributed_on) { rate(rent_envelope, 400) }

    expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
  end

  # A REALLOCATION IS NOT A DISTRIBUTION. `PoolMovement.distributed` is allocations and sweeps;
  # a `transfer` is Task 7's screen moving money between two envelopes, and it hands nothing
  # out. Written with the same shape and the same clock as the positive example, so only the
  # `kind` differs.
  it "is false when the only movement this period is a transfer" do
    rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
    distribute(400, kind: :transfer)
    raise_rule(rule, to: 470, at: distributed_on + 2.hours)

    expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
  end

  # LAST PERIOD'S DISTRIBUTION IS NOT THIS ONE'S. The clause explains a flip that happened since
  # the money was handed out; a split from a fortnight ago says nothing about it, and reading it
  # would mark every rule edited since as "raised after distributing" forever.
  # `on:` puts the split in the PREVIOUS biweekly period (the user is anchored to Feb 6, so this
  # period opens that day and the one before it ran Jan 23 – Feb 5). Both the `date` and the
  # `created_at` fall outside; it is the `date` bound that excludes it, which is the bound
  # AllocationCommitter uses to find the split it replaces.
  it "is false when the only distribution belongs to an earlier period" do
    rule = travel_to(distributed_on - 20.days) { rate(rent_envelope, 400) }
    distribute(400, at: distributed_on - 18.days, on: today - 14.days)
    raise_rule(rule, to: 470, at: distributed_on - 17.days)

    expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
  end

  # A SWEEP DATES A DISTRIBUTION TOO. A period whose split is pure sweep — every envelope closed
  # and nothing re-funded — writes no allocation at all, and reading `from_pool_id` alone would
  # miss it entirely.
  it "counts a sweep as this period's distribution" do
    rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
    travel_to(distributed_on) do
      create(:pool_movement, kind: :sweep, from_pool: rent_envelope, to_pool: checking, amount: 50, date: today)
    end
    raise_rule(rule, to: 470, at: distributed_on + 2.hours)

    expect(clock.changed_after_distributing?(rent_envelope)).to be(true)
  end

  # THE TOUCH CASCADE, MEASURED RATHER THAN REASONED ABOUT. `touch: true` is everywhere on this
  # schema — `PoolMovement belongs_to :from_pool/:to_pool, touch: true`, and a pool touches its
  # user — and if any of it reached `budgets` this clause would fire on every user who
  # distributed and changed nothing. It does not: `Budget belongs_to :pool, touch: true` points
  # the other way, and no association anywhere declares `belongs_to :budget, touch: true`.
  #
  # Asserted on the COLUMN and then on the reader, because the second alone would pass if the
  # comparison were broken in the same direction as the cascade.
  it "is not moved by the distribution's own touch cascade", :aggregate_failures do
    rule = travel_to(distributed_on - 1.day) { rate(rent_envelope, 400) }
    before_at = rule.reload.updated_at

    distribute(400)

    expect(rule.reload.updated_at).to eq(before_at)
    expect(rent_envelope.reload.updated_at).to be > before_at
    expect(clock.changed_after_distributing?(rent_envelope)).to be(false)
  end

  # A pool with no account has no distribution to be after — nothing can fund it at all — and a
  # missing key must read as "no distribution" rather than raise.
  it "is false for a pool no account can reach" do
    orphan = create(:pool, user: user, name: "Retirement Supplement", target_amount: 5_000, priority: 1)
    travel_to(distributed_on) { create(:pool_budget, :per_period_rate, pool: orphan, amount: 150) }
    distribute(400)

    expect(clock.changed_after_distributing?(orphan)).to be(false)
  end

  # THE EMPTY SET COSTS NO QUERY, which is the one branch nothing else reaches: a user with no
  # accounts makes the whole question moot, and `#latest` answers `{}` rather than sending an `IN ()`
  # to Postgres. Asserted by counting statements, because the RESULT is the same either way.
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
