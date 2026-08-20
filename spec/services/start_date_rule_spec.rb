# frozen_string_literal: true

require "rails_helper"

# THE START-DATE RULE (main-account spec §3): an envelope or goal only counts category
# spending dated on or after the pool's start_date; earlier entries read against the user's
# main account. The envelope's date governs — never the category's connection date.
RSpec.describe "The start-date rule", type: :model do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:envelope) do
    create(:pool, :budget_pool, user: user, account: main, name: "Food", start_date: Date.new(2026, 8, 1))
  end
  let(:category) { create(:category, :expense, user: user, pool: envelope, name: "Food") }
  let(:item) { create(:item, category: category) }

  before { user.update!(default_account: main) }

  def balance(pool)
    PoolCalculator.new(pool).balance
  end

  it "sends pre-start spending to the main account, post-start to the envelope", :aggregate_failures do
    create(:entry, item: item, amount: 100, date: Date.new(2026, 7, 31)) # before
    create(:entry, item: item, amount: 40, date: Date.new(2026, 8, 1)) # on the day

    expect(balance(envelope)).to eq(-40)
    expect(balance(main)).to eq(-100)
  end

  it "leaves the override lane above the rule: a pinned entry lands where it is pinned" do
    create(:entry, item: item, amount: 25, date: Date.new(2026, 7, 1), pool: envelope)

    expect(balance(envelope)).to eq(-25)
  end

  it "exempts account pools: a category on the main account has no date gate" do
    on_main = create(:category, :expense, user: user, pool: main, name: "Misc")
    create(:entry, item: create(:item, category: on_main), amount: 10, date: Date.new(2020, 1, 1))

    expect(balance(main)).to eq(-10)
  end

  it "still sends a pool-less category's entries to no pool at all", :aggregate_failures do
    # Planted past the model: the required belongs_to would refuse this shape.
    loose = build(:category, :expense, user: user, pool: nil, name: "Loose")
    loose.save!(validate: false)
    create(:entry, item: create(:item, category: loose), amount: 5, date: Date.current)

    expect(balance(main)).to eq(0)
    expect(balance(envelope)).to eq(0)
  end

  # THE OTHER SHAPE `Category#pool_must_be_reachable` (main-account spec §6) EXISTS TO REFUSE:
  # an envelope category for a user with no main account at all. The ELSE arm of the landing rule
  # (`PoolBalanceLedger::ENTRY_POOL_ID`, and `Category#effective_pool` beside it) sends a pre-start
  # entry to `user&.default_account` — a NULL there resolves the whole COALESCE to nothing, so the
  # entry reaches no pool and Σ pools drops below bank truth by exactly its amount. The validator
  # is what keeps this from happening for real; this proves it is worth keeping.
  it "loses a pre-start entry from every pool when the category's user has no main account", :aggregate_failures do
    # Planted past the model: Category#pool_must_be_reachable would refuse an envelope category
    # for a user with no default_account.
    orphaned = build(:category, :expense, user: user, pool: envelope, name: "Orphaned")
    user.update!(default_account: nil)
    orphaned.save!(validate: false)
    create(:entry, item: create(:item, category: orphaned), amount: 15, date: Date.new(2026, 7, 1))

    expect(balance(main)).to eq(0)
    expect(balance(envelope)).to eq(0)

    pool_side = user.pools.sum { |pool| PoolCalculator.new(pool).balance }
    # M8 (fix round 2): THE EXACT GAP, not just a mismatch — pool_side is HIGHER than bank truth
    # by precisely this entry's $15, the amount that fell out of every pool while the bank
    # ledger still counts it. An inequality alone would pass on any wrong number at all.
    expect(bank_truth_for(user) - pool_side).to eq(-15)
  end

  # THE BOUNDARY DAY IS THE USER'S DAY, NOT UTC'S. `entries.date` is a DATETIME column and
  # ApplicationController wraps every request in `Time.use_zone(current_user.timezone)`, so an entry
  # a Tokyo user files on Aug 1 is stored `2026-07-31 15:00:00` — nine hours before the UTC day
  # begins. Compared raw against a DATE, that entry is "before" a start date it is actually on, and
  # the rule would exile every east-of-UTC user's first-day spending to main.
  #
  # BOTH SIDES OF ONE MIDNIGHT, an hour apart, so the example pins where the line falls rather than
  # that a line exists: 15:00 UTC is Tokyo's Aug 1 and lands in the envelope, 14:00 UTC is still
  # Tokyo's Jul 31 and lands in main.
  it "reads the boundary in the user's own timezone rather than UTC", :aggregate_failures do
    user.update!(timezone: "Asia/Tokyo")
    create(:entry, item: item, amount: 30, date: Time.utc(2026, 7, 31, 15, 0))
    create(:entry, item: item, amount: 7, date: Time.utc(2026, 7, 31, 14, 0))

    expect(balance(envelope)).to eq(-30)
    expect(balance(main)).to eq(-7)
  end

  it "keeps Σ pools == bank truth while relocating, by raw SQL on both sides" do
    create(:entry, item: item, amount: 100, date: Date.new(2026, 7, 31))
    create(:entry, item: item, amount: 40, date: Date.new(2026, 8, 2))
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 500, date: Date.current)

    pool_side = user.pools.sum { |pool| PoolCalculator.new(pool).balance }

    expect(pool_side).to eq(bank_truth_for(user))
  end

  # The bank's side of the invariant, keyed by CATEGORY OWNERSHIP rather than by pool membership —
  # the one thing under test — and read from `entries` alone so no app reader refereeing itself.
  def bank_truth_for(user)
    ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric ELSE -e.amount::numeric END)
      FROM entries e
      JOIN items i ON i.id = e.item_id
      JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
  end
end
