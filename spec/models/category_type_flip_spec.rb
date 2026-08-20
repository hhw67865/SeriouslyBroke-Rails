# frozen_string_literal: true

require "rails_helper"

# I-3 (final whole-branch review, main-account spec §4): FLIPPING A CATEGORY OUT OF INCOME TAKES
# ITS ENTRIES' MIRROR MOVEMENTS WITH IT.
#
# An income entry always LANDS in main; saying it ended up in Ally writes ONE `transfer` movement
# main → Ally against that entry. `EntriesController#sync_income_routing` is the only other caller
# of `Entry#route_income_to!` and it syncs ENTRY-side only — so `category_type`, which the ordinary
# category edit form permits, could be flipped income → expense and leave every mirror standing:
# main debited for money the app no longer thinks arrived, the destination holding a phantom.
#
# Every figure below is a planted literal, and the rule is pinned in both directions — the flip
# that clears, beside the two updates that must clear nothing.
RSpec.describe "Category type flips", type: :model do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:pay) { create(:category, :income, user: user, pool: main, name: "Pay") }
  let(:paycheck) { create(:entry, item: create(:item, category: pay), amount: 500, date: Date.current) }

  before do
    user.update!(default_account: main)
    paycheck.route_income_to!(ally)
  end

  def routing_count(entry) = PoolMovement.kind_transfer.where(source_entry: entry).count

  it "destroys the routing movements of its entries and hands the money back to main", :aggregate_failures do
    expect(routing_count(paycheck)).to eq(1)
    expect(ally.calculator.balance).to eq(500)

    pay.update!(category_type: :expense)

    expect(routing_count(paycheck)).to eq(0)
    # THE DESTINATION IS EMPTIED, which is the half a user would have seen as a phantom balance.
    expect(ally.calculator.balance).to eq(0)
    # AND MAIN IS DEBITED ONCE, NOT TWICE. The entry is an expense now, so main reads -$500 — had
    # the mirror survived, the same $500 would have left main a second time and main would read
    # -$1,000 against a bank that saw one $500 transaction.
    expect(main.calculator.balance).to eq(-500)
  end

  # `kind_transfer` IS LOAD-BEARING IN THE SWEEP, not decoration: allocation and sweep movements
  # carry a `source_entry` too — that link is what makes a distribution replaceable — so a callback
  # that went by the link alone would delete the period's envelope split every time somebody
  # re-typed a category.
  it "leaves the distribution's own movements alone", :aggregate_failures do
    groceries = create(:pool, :budget_pool, user: user, account: main, name: "Groceries")
    allocation = PoolMovement.create!(
      from_pool: main, to_pool: groceries, amount: 120, date: Date.current, kind: :allocation, source_entry: paycheck
    )

    pay.update!(category_type: :expense)

    expect(allocation.reload).to be_persisted
    expect(groceries.calculator.balance).to eq(120)
  end

  # THE GUARD IS THE EXACT PAIR, income → expense, and these two prove it from the other side.
  it "destroys nothing when an expense category becomes income", :aggregate_failures do
    spending = create(:category, :expense, user: user, pool: main, name: "Misc")
    outgoing = create(:entry, item: create(:item, category: spending), amount: 40, date: Date.current)
    # Planted directly: an expense entry never gets a mirror through the app, so this row exists
    # only to prove the callback does not reach for it on a flip in the other direction.
    PoolMovement.create!(
      from_pool: main, to_pool: ally, amount: 40, date: Date.current, kind: :transfer, source_entry: outgoing
    )

    spending.update!(category_type: :income)

    expect(routing_count(outgoing)).to eq(1)
  end

  it "destroys nothing when an income category is merely renamed", :aggregate_failures do
    pay.update!(name: "Salary")

    expect(routing_count(paycheck)).to eq(1)
    expect(ally.calculator.balance).to eq(500)
  end
end
