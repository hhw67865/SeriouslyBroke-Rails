# frozen_string_literal: true

require "rails_helper"

# THE TWO-LEDGER INVARIANT (spec §2): pot + Σ accounts == income − expenses == available +
# Σ category holdings. Both partitions computed by the app's own readers; bank truth by raw SQL.
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
    create(:pool_movement, from_pool: main, to_pool: ally, amount: 200, date: Time.zone.parse("2026-08-08 12:00"))
    create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-09 12:00")) # back to available

    expect(bank_truth).to eq(925)
    expect(physical).to eq(925)
    expect(purpose).to eq(925)
    expect(CategoryLedger.new([food]).holding_of(food)).to eq(210) # 300 − 40 − 50; the $10 predates funding
    expect(CategoryLedger.new([food, misc]).available).to eq(715) # 1000 − 25 − 10 − 300 + 50
  end
  # rubocop:enable RSpec/ExampleLength
end
