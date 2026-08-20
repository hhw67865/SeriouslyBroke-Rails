# frozen_string_literal: true

require "rails_helper"

# INCOME ROUTING (main-account spec §4): the entry always lands in main; choosing another
# account writes ONE mirroring movement main → account, linked by source_entry_id so edits
# and deletes find it. Expenses never route.
#
# THE REQUEST LAYER IS WHERE THE VIRTUAL PARAM LIVES. `destination_account_id` is never a column
# on `entries` — it is a question the form asks and the controller answers by writing a movement —
# so the shape of the write, its scoping and its idempotence are all facts about a request rather
# than about a record. Every figure below is a planted literal, and each rule is pinned in BOTH
# directions: routed beside not-routed, owner's account beside a stranger's.
RSpec.describe "Entries income routing", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:income) { create(:category, :income, user: user, pool: main, name: "Pay") }
  let(:pay_item) { create(:item, category: income, name: "Paycheck") }

  let(:groceries_pool) { create(:pool, :budget_pool, user: user, account: main, name: "Groceries") }
  let(:expense) { create(:category, user: user, pool: groceries_pool, name: "Food", category_type: :expense) }
  let(:food_item) { create(:item, category: expense, name: "Bananas") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  def routing_for(entry) = entry.pool_movements.kind_transfer

  def post_income(destination:, amount: 500)
    post entries_path,
         params: {
           entry: {
             item_id: pay_item.id,
             amount: amount,
             date: Date.current.iso8601,
             destination_account_id: destination
           }
         }
    Entry.order(:created_at).last
  end

  describe "creating income" do
    it "writes the linked movement when income lands elsewhere", :aggregate_failures do
      entry = post_income(destination: ally.id)
      movement = routing_for(entry).sole

      expect(movement.from_pool).to eq(main)
      expect(movement.to_pool).to eq(ally)
      expect(movement.amount).to eq(500)
      expect(movement.date).to eq(Date.current)
    end

    it "writes no movement when income lands in main" do
      expect(routing_for(post_income(destination: main.id))).to be_empty
    end

    it "writes no movement when the destination is left blank" do
      expect(routing_for(post_income(destination: ""))).to be_empty
    end
  end

  describe "editing" do
    it "removes the movement on a re-route back to main" do
      entry = post_income(destination: ally.id)

      patch entry_path(entry), params: { entry: { destination_account_id: main.id } }

      expect(routing_for(entry)).to be_empty
    end

    it "replaces rather than duplicates on a re-route to a third account", :aggregate_failures do
      third = create(:pool, :account, user: user, name: "Third")
      entry = post_income(destination: ally.id)

      patch entry_path(entry), params: { entry: { destination_account_id: third.id } }

      expect(routing_for(entry).sole.to_pool).to eq(third)
    end

    it "keeps the movement in step with an amount edit" do
      entry = post_income(destination: ally.id)

      patch entry_path(entry), params: { entry: { amount: 750, destination_account_id: ally.id } }

      expect(routing_for(entry).sole.amount).to eq(750)
    end

    # THE BINDING RESOLUTION: only an EXPLICIT param changes routing. A caller that never asks the
    # question — an edit posted without the select — must leave the answer standing rather than
    # silently un-routing a paycheck.
    it "leaves routing untouched when the param is not submitted at all", :aggregate_failures do
      entry = post_income(destination: ally.id)

      patch entry_path(entry), params: { entry: { amount: 750 } }

      expect(routing_for(entry).sole.to_pool).to eq(ally)
      expect(routing_for(entry).sole.amount).to eq(750)
    end

    # THE DATE ARM OF THE SAME RE-SYNC. `#route_income_to!` copies BOTH figures off the entry, so
    # both have to be pinned: a mirror stamped with the day the paycheck was first recorded rather
    # than the day it actually arrived would put main's outflow in one period and Ally's inflow in
    # another, and every period-bounded reader would disagree with the next by that amount.
    it "keeps the movement in step with a date edit when the param is not submitted" do
      entry = post_income(destination: ally.id)
      corrected = 3.days.ago.to_date

      patch entry_path(entry), params: { entry: { date: corrected.iso8601 } }

      expect(routing_for(entry).sole.date.to_date).to eq(corrected)
    end

    it "drops the routing when the entry stops being income" do
      entry = post_income(destination: ally.id)

      patch entry_path(entry), params: { entry: { item_id: food_item.id } }

      expect(routing_for(entry)).to be_empty
    end

    it "takes the movement with the entry on delete" do
      entry = post_income(destination: ally.id)

      expect { delete entry_path(entry) }.to change(PoolMovement, :count).by(-1)
    end
  end

  describe "expenses" do
    it "never routes, even when a destination is submitted" do
      post entries_path,
           params: {
             entry: {
               item_id: food_item.id,
               amount: 40,
               date: Date.current.iso8601,
               destination_account_id: ally.id
             }
           }

      expect(routing_for(Entry.order(:created_at).last)).to be_empty
    end
  end

  describe "scoping" do
    it "refuses to route to an account that is not the user's" do
      post_income(destination: create(:pool, :account, user: create(:user)).id)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses to route to a pool of the user's that is not an account" do
      post_income(destination: groceries_pool.id)

      expect(response).to have_http_status(:not_found)
    end

    it "saves nothing when the destination is refused" do
      expect { post_income(destination: groceries_pool.id) }.not_to change(Entry, :count)
    end
  end

  # THE APP'S ONE INVARIANT, ASKED OF THE FEATURE THAT MOVES MONEY WITHOUT EARNING IT.
  #
  # `Σ pools == your bank balance`. A routing movement is a transfer BETWEEN two of the user's own
  # pools, so it must net to exactly zero across them — the $500 leaves main and arrives in Ally,
  # and the bank never sees it. The two ways this feature could break that are the two ways it is
  # written: counting the paycheck in main AND in Ally (a missing outflow) or in neither (an
  # outflow with no inflow), and NEITHER shows up in any per-pool assertion above, because each of
  # those reads one pool at a time.
  #
  # BOTH SIDES COMPUTED INDEPENDENTLY, house precedent `spec/services/start_date_rule_spec.rb`: the
  # pool side by PoolCalculator, the bank side by raw SQL over `entries → items → categories` and
  # keyed on CATEGORY OWNERSHIP, so no app reader referees itself. The expense is here so the sum
  # is not trivially the one income figure on both sides: $500 in, $40 out, $460 either way.
  it "keeps Σ pools == bank truth with the income routed away from main" do
    post_income(destination: ally.id)
    create(:entry, item: food_item, amount: 40, date: Date.current)

    pool_side = user.pools.sum { |pool| PoolCalculator.new(pool).balance }

    expect(pool_side).to eq(bank_truth_for(user))
  end

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
