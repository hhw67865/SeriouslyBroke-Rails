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
  let(:income) { create(:category, :income, user: user, name: "Pay") }
  let(:pay_item) { create(:item, category: income, name: "Paycheck") }

  let(:expense) { create(:category, user: user, name: "Food", category_type: :expense) }
  let(:food_item) { create(:item, category: expense, name: "Bananas") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  def routing_for(entry) = entry.account_movements.kind_transfer

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

      expect { delete entry_path(entry) }.to change(AccountMovement, :count).by(-1)
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

    # "refuses to route to a pool of the user's that is not an account" IS DELETED WITH THE SHAPE
    # (two-ledger spec §5, Task 8): `pools_are_accounts` makes an envelope id unwritable, so the
    # type half of `current_user.pools.pool_type_account.find` has nothing left to exclude. The
    # OWNERSHIP half above is the whole of what the scoping still decides.
    it "saves nothing when the destination is refused" do
      expect { post_income(destination: create(:pool, :account, user: create(:user)).id) }
        .not_to change(Entry, :count)
    end
  end

  # THE APP'S ONE INVARIANT, ASKED OF THE FEATURE THAT MOVES MONEY WITHOUT EARNING IT.
  #
  # `pot + Σ accounts == your bank balance` (§2). A routing movement is a transfer BETWEEN two of
  # the user's own accounts, so it must net to exactly zero across them — the $500 leaves main and
  # arrives in Ally, and the bank never sees it. The two ways this feature could break that are the
  # two ways it is written: counting the paycheck in main AND in Ally (a missing outflow) or in
  # neither (an outflow with no inflow), and NEITHER shows up in any per-account assertion above,
  # because each of those reads one account at a time.
  #
  # BOTH SIDES COMPUTED INDEPENDENTLY: the physical side through `AccountLedger`, one account at a
  # time and summed in Ruby, and the bank side by raw SQL over `entries → items → categories` keyed
  # on CATEGORY OWNERSHIP, so no app reader referees itself. The expense is here so the sum is not
  # trivially the one income figure on both sides: $500 in, $40 out, $460 either way.
  it "keeps pot + Σ accounts == bank truth with the income routed away from main" do
    post_income(destination: ally.id)
    create(:entry, item: food_item, amount: 40, date: Date.current)

    ledger = AccountLedger.new(user)
    account_side = user.pools.accounts.sum { |account| ledger.balance_of(account) }

    expect(account_side).to eq(bank_truth_for(user))
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
  # ** AN OPENING ENTRY'S ACCOUNT IS NOT EDITABLE FROM THE ENTRIES SCREEN (fix round — MED-1). **
  #
  # The select on this form is the door onto `Entry#route_income_to!`, which REWRITES the entry's
  # transfer — and for an opening entry that transfer is half the record of what an account holds
  # (account-openings §2). Measured before the guard: re-pointing Ally's opening at HYSA moved the
  # $500 transfer with it, so Ally's next **Edit balance** computed `typed − balance − 500` and an
  # Ally corrected to $1,000 showed $500, while HYSA silently held the difference.
  #
  # THREE PINS, AND THE THIRD IS THE ONE THAT MATTERS: the refusal is only worth anything if the
  # account it protected still corrects to the figure the user types afterwards.
  describe "an opening entry" do
    let(:hysa) { create(:pool, :account, user: user, name: "HYSA") }

    def open!(account, balance)
      opening = AccountOpening.new(user, account, balance: balance)
      raise "could not open #{account.name}" unless opening.save

      Entry.find_by!(opening_account_id: account.id)
    end

    # THE VIEW HALF: no select is rendered at all, and the read-only line names the account it
    # belongs to and where to change it. Asserted on the response body rather than in a system spec
    # because what is under test is a SERVER decision about which control to draw.
    it "is offered a read-only line instead of the account select", :aggregate_failures do
      entry = open!(ally, "500")

      get edit_entry_path(entry)

      expect(response.body).not_to include('name="entry[destination_account_id]"')
      expect(response.body).to include("Opening balance for Ally")
      expect(response.body).to include(Entry::OPENING_DOOR)
    end

    # AN ORDINARY INCOME ENTRY IS UNTOUCHED BY THE GUARD, which is the other direction of the same
    # render: the question is still asked wherever a saved category can answer it.
    it "leaves the select on an ordinary income entry" do
      entry = post_income(destination: ally.id)

      get edit_entry_path(entry)

      expect(response.body).to include('name="entry[destination_account_id]"')
    end

    # THE WIRE HALF: a stale form and a crafted POST both reach `#update`, and both are refused with
    # the same sentence the form prints — nothing written, 422, the movement still where it was.
    it "refuses a re-point through the wire", :aggregate_failures do
      entry = open!(ally, "500")

      patch entry_path(entry), params: { entry: { destination_account_id: hysa.id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Opening balance for Ally")
      expect(routing_for(entry.reload).sole.to_pool).to eq(ally)
      expect(AccountLedger.new(user).balance_of(hysa)).to eq(0)
    end

    # ** AND THE CORRECTION AFTER A REFUSED RE-POINT STILL READS THE TYPED FIGURE. ** Re-derived:
    # Ally opened at $500 and nothing has flowed through it since, so saying it holds $1,000 sets its
    # opening to $1,000 — which is exactly what the un-guarded re-point broke, and the reason the
    # 422 above is worth having.
    it "still corrects to the figure the user types", :aggregate_failures do
      entry = open!(ally, "500")
      patch entry_path(entry), params: { entry: { destination_account_id: hysa.id } }

      patch bank_account_opening_path(ally), params: { account_opening: { balance: "1000" } }

      expect(AccountLedger.new(user).balance_of(ally)).to eq(1_000)
      expect(AccountLedger.new(user).balance_of(hysa)).to eq(0)
      expect(Entry.where.not(opening_account_id: nil).count).to eq(1)
    end

    # ** THE AMOUNT IS NOT EDITABLE HERE EITHER (fix round round 2 — item 1), AND THE FIRST ROUND HAD
    # IT WRONG. ** This example used to assert that $500 → $600 went through; it does not, because
    # the entry is only HALF the record and the movement beside it was left on the old figure. One
    # door, and it is the account's card.
    it "refuses an amount edited from this screen", :aggregate_failures do
      entry = open!(ally, "500")

      patch entry_path(entry), params: { entry: { amount: "600" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Entry::OPENING_DOOR)
      expect(entry.reload.amount).to eq(500)
      expect(routing_for(entry).sole.amount).to eq(500)
    end

    # ** ZERO WAS A 500, AND IT DESTROYED THE MOVEMENT ON THE WAY (fix round round 2 — item 1). **
    # Zero passes `Entry`'s validation on an opening row, so the save succeeded and
    # `#sync_income_routing` then tried to mirror it: `route_income_to!` cleared the real movement
    # and `create!(amount: 0)` hit `account_movements_positive_amount` — an unhandled
    # `PG::CheckViolation` AFTER the delete, leaving the account holding money nothing had moved.
    it "refuses a zero amount without touching the movement", :aggregate_failures do
      entry = open!(ally, "500")

      patch entry_path(entry), params: { entry: { amount: "0" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(entry.reload.amount).to eq(500)
      expect(routing_for(entry).sole.amount).to eq(500)
      expect(AccountLedger.new(user).balance_of(ally)).to eq(500)
    end

    # ** A NEGATIVE OPENING'S FORM, SAVED WITH NOTHING CHANGED, USED TO DELETE ITS TRANSFER. ** Such
    # an entry sits in the EXPENSE-typed `Opening Shortfall` category, so `#sync_income_routing`'s
    # first line — "an entry that is not income clears its routing" — fired `route_income_to!(nil)`
    # on every save of that form, including one that changed only the description. The transfer runs
    # account → main for a negative opening and `AccountOpening` owns it; this screen is skipped
    # entirely now. Re-derived: $900 moved into Ally, the user says it holds $400, so the opening is
    # 400 − 900 = −$500 and the transfer is Ally → main for $500.
    it "leaves a shortfall opening's transfer alone on an unchanged save", :aggregate_failures do
      create(:account_movement, from_pool: main, to_pool: ally, amount: 900, date: Date.current, kind: :transfer)
      entry = open!(ally, "400")
      expect(entry.category.name).to eq(Category::OPENING_SHORTFALL_NAME)

      patch entry_path(entry), params: { entry: { description: "typed a note" } }

      expect(response).to redirect_to(entries_path)
      movement = routing_for(entry.reload).sole
      expect(movement.from_pool).to eq(ally)
      expect(movement.amount).to eq(500)
      expect(AccountLedger.new(user).balance_of(ally)).to eq(400)
    end

    # THE DATE AND THE DESCRIPTION ARE STILL EDITABLE — neither is part of the arithmetic, and an
    # unchanged amount is not an edit, which is what lets the ordinary "open the form and press
    # Save" through.
    it "still takes a date edit and an unchanged amount", :aggregate_failures do
      entry = open!(ally, "500")

      patch entry_path(entry), params: { entry: { amount: "500.0", date: "2026-01-02" } }

      expect(response).to redirect_to(entries_path)
      expect(entry.reload.date.to_date).to eq(Date.new(2026, 1, 2))
      expect(routing_for(entry).sole.amount).to eq(500)
    end
  end
end
