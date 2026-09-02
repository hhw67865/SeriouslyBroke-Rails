# frozen_string_literal: true

require "rails_helper"

# THE TWO-LEDGER INVARIANT (spec §2): pot + Σ accounts == income − expenses == available +
# Σ category holdings. Both partitions computed by the app's own readers; bank truth by raw SQL.
#
# THE CONVENTION, STATED ONCE AND DELIBERATE: the two PARTITIONS are read through `AccountLedger` and
# `CategoryLedger` — the app's own readers — while only the ANCHOR they are compared against is raw
# SQL. Respelling either ledger in SQL here would be a second spelling of a reader this file exists
# to check, agreeing with the first by whoever last edited both; the raw-SQL anchor answers a
# question neither reader can be wrong about in the same direction, which is whether money was
# created or destroyed at all.
RSpec.describe "The two-ledger invariant", type: :model do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:food) { create(:category, :expense, :funded, user: user, name: "Food", funded_since: Date.new(2026, 8, 1)) }
  let(:misc) { create(:category, :expense, user: user, name: "Misc") } # never funded
  let(:pay) { create(:category, :income, user: user, name: "Pay") }

  before { user.update!(default_account: main) }

  def bank_truth
    ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_d
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
  end

  def physical = AccountLedger.new(user).then { |l| l.pot + l.balance_of(ally) }

  def purpose = CategoryLedger.new(user.categories.expenses).then { |l| l.available + [food, misc].sum { |c| l.holding_of(c) } }

  # rubocop:disable RSpec/ExampleLength
  # SEVEN WRITES AND FIVE FIGURES, and the length is the point: the invariant is a statement about
  # a world with every kind of row in it at once, so an example that plants three of them proves
  # only that three of them cancel.
  it "holds after income, allocation, funded and unfunded spending, an account transfer, and a savings round-trip", :aggregate_failures do
    create(:entry, item: create(:item, category: pay), amount: 1000, date: Date.new(2026, 8, 5))
    create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-08-06 12:00"))
    create(:entry, item: create(:item, category: food), amount: 40, date: Date.new(2026, 8, 7)) # funded
    create(:entry, item: create(:item, category: misc), amount: 25, date: Date.new(2026, 8, 7)) # unfunded
    create(:entry, item: create(:item, category: food), amount: 10, date: Date.new(2026, 7, 20)) # pre-funded
    create(:account_movement, from_pool: main, to_pool: ally, amount: 200, date: Time.zone.parse("2026-08-08 12:00"))
    create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-09 12:00")) # back to available

    expect(bank_truth).to eq(925)
    expect(physical).to eq(925)
    expect(purpose).to eq(925)
    expect(CategoryLedger.new([food]).holding_of(food)).to eq(210) # 300 − 40 − 50; the $10 predates funding
    expect(CategoryLedger.new([food, misc]).available).to eq(715) # 1000 − 25 − 10 − 300 + 50
  end

  # THE KEYSTONE FOR TASK 4: a distribution is the biggest single write on the purpose ledger — a
  # sweep out of every closed category and an allocation into every one that asks — and it must move
  # money without creating or destroying any.
  #
  # Both sides are read the same way BEFORE and AFTER, and the equality is against the raw-SQL bank
  # truth rather than against the app's own other reader: $1,000 came in and nothing went out, so
  # both partitions are $1,000 whatever the split did. A committer that wrote an allocation with no
  # sweep behind it, or doubled a row, moves one of these two figures and nothing else would say so.
  #
  # THE FIGURES ARE PLANTED, not derived: Food has a $400 rate rule and holds $120 of a period that
  # closed, so the split sweeps $120 back and hands $400 out — leaving Food at $400 and available at
  # $600, which is $1,000 between them, twice over.
  it "holds after a committed distribution: income 1000 in, 1000 across both ledgers after" do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6))
    # `misc` is referenced so the lazy `let` exists BEFORE `#purpose` builds its ledger — that reader
    # sums `[food, misc]` and `CategoryLedger#holding_of` raises rather than answering zero for a
    # category it was not built over, which is the guard doing its job on a fixture ordering mistake.
    misc
    food.update!(priority: 1)
    create(:budget, :per_period_rate, category: food, amount: 400)
    create(:entry, item: create(:item, category: pay), amount: 1000, date: Date.new(2026, 8, 5))
    create(:allocation, to_category: food, amount: 120, date: Time.zone.parse("2026-07-12 12:00"))

    result = AllocationCommitter.new(AllocationCalculator.new(user: user, today: Date.new(2026, 8, 20))).call

    aggregate_failures do
      expect(result.success?).to be(true)
      expect([result.swept, result.allocated]).to eq([120, 400])
      expect(bank_truth).to eq(1_000)
      expect(physical).to eq(1_000)
      expect(purpose).to eq(1_000)
      expect(CategoryLedger.new([food]).holding_of(food)).to eq(400)
      expect(CategoryLedger.new(user.categories.expenses).available).to eq(600)
    end
  end
  # rubocop:enable RSpec/ExampleLength
end
