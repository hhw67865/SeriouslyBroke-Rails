# frozen_string_literal: true

require "rails_helper"

# DESTROYING A POOL NO LONGER CORRUPTS ITS NEIGHBOURS — spec §7a's "reconsider
# `dependent: :destroy` on `movements_out`", measured.
#
# THE INVARIANT IS NOT THE TEST HERE, and that is the whole reason this file exists separately.
# `Σ pools == your bank balance` SURVIVES the old behaviour: every movement is a transfer between
# two of the user's own pools, so deleting one nets to zero in the tree and the total is unmoved
# whether the neighbours were corrupted or not. Asserting conservation alone would pass against
# the defect. What breaks is INDIVIDUAL balances, so every example below pins a named pool's
# figure — the sibling's unchanged, the buffer's up by exactly the destroyed pool's balance —
# against a literal computed from the fixture's own arithmetic, and the conservation assertions
# are pinned against the PLANTED deposit rather than against `Pool#total`'s own parts (which is
# the sum of those parts by definition, and would assert nothing).
RSpec.describe Pool, "#destroy", type: :model do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # THE ONLY MONEY PLANTED ANYWHERE IN THIS FILE. Every conservation assertion is pinned against
  # this literal — income that entered the user's life, which no movement can create or destroy.
  # A method rather than a constant so it cannot leak out of the example group.
  def deposit = 500

  def pay(pool, amount, named:, on: Date.current)
    category = create(:category, :income, user: pool.user, pool: pool, name: named)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A FRESH calculator every time. PoolCalculator memoises its balance and is stale after a
  # write, and a destroy is a write — a calculator held across one answers about the ledger as
  # it was, which is the exact staleness this task's assertions have to see through.
  def balance(pool) = pool.calculator.balance

  # `Pool#total` off a freshly loaded record, so a `child_pools` collection cached before the
  # destroy cannot keep a deleted envelope in the sum.
  def total_of(account) = described_class.find(account.id).total

  # ── THE CHAIN THE §7a NOTE DESCRIBES ──────────────────────────────────────────────────────
  # $500 of income lands in Checking. Checking → B $100 (an allocation), B → C $60 (a transfer),
  # so B is left holding $40 and C is holding $60. Destroying B used to delete BOTH rows, which
  # took C's $60 inflow with it.
  describe "an envelope in the middle of a chain" do
    let(:envelope_b) { create(:pool, :budget_pool, user: user, account: checking, name: "B") }
    let(:envelope_c) { create(:pool, :budget_pool, user: user, account: checking, name: "C") }
    let!(:allocation) do
      create(:pool_movement, from_pool: checking, to_pool: envelope_b, amount: 100, kind: :allocation)
    end
    let!(:transfer) do
      create(:pool_movement, from_pool: envelope_b, to_pool: envelope_c, amount: 60, kind: :transfer)
    end

    before { pay(checking, deposit, named: "Salary") }

    it "starts from the figures the fixture planted", :aggregate_failures do
      expect(balance(checking)).to eq(400) # 500 paid in, 100 allocated out
      expect(balance(envelope_b)).to eq(40) # 100 in, 60 out
      expect(balance(envelope_c)).to eq(60)
      expect(total_of(checking)).to eq(deposit)
    end

    it "leaves the far end of the chain holding exactly what it held", :aggregate_failures do
      expect(balance(envelope_c)).to eq(60)

      expect(envelope_b.destroy).to be_truthy

      expect(balance(envelope_c)).to eq(60)
      expect(balance(envelope_c)).to be_a(BigDecimal)
    end

    it "raises the buffer by exactly the destroyed envelope's balance", :aggregate_failures do
      expect(balance(checking)).to eq(400)
      expect(balance(envelope_b)).to eq(40)

      envelope_b.destroy

      expect(balance(checking)).to eq(440) # 400 + B's own 40, and nothing else
      expect(balance(checking)).to be_a(BigDecimal)
    end

    # The row itself, not its effect: a balance assertion alone is satisfied by a ledger that
    # deleted the transfer and invented a $60 line from somewhere else.
    it "re-points the surviving transfer to the account, keeping its amount and its kind", :aggregate_failures do
      envelope_b.destroy
      transfer.reload

      expect(transfer.from_pool).to eq(checking)
      expect(transfer.to_pool).to eq(envelope_c)
      expect(transfer.amount).to eq(60)
      expect(transfer.kind).to eq("transfer")
    end

    # Checking → B re-points to Checking → Checking, which is not a movement.
    it "destroys the allocation that collapses to account → account", :aggregate_failures do
      expect { envelope_b.destroy }.to change(PoolMovement, :count).from(2).to(1)

      expect(PoolMovement.exists?(allocation.id)).to be(false)
      expect(PoolMovement.exists?(transfer.id)).to be(true)
    end

    # Pinned against deposit — the money that actually entered the user's life — on both sides,
    # never against `checking.calculator.balance + b + c`, which is what `#total` already is.
    it "keeps Σ pools equal to the money that was actually paid in", :aggregate_failures do
      expect(total_of(checking)).to eq(deposit)

      envelope_b.destroy

      expect(total_of(checking)).to eq(deposit)
      expect(total_of(checking)).to be_a(BigDecimal)
    end

    it "takes the envelope itself with it" do
      expect { envelope_b.destroy }.to change { described_class.exists?(envelope_b.id) }.from(true).to(false)
    end

    # `dependent: :destroy` walks the association's loaded target, so a caller that read the
    # movements before deleting must not hand it a cached list of rows that have since moved.
    it "survives a caller that loaded the movements before destroying", :aggregate_failures do
      envelope_b.movements_in.load
      envelope_b.movements_out.load

      envelope_b.destroy

      expect(PoolMovement.exists?(transfer.id)).to be(true)
      expect(balance(envelope_c)).to eq(60)
    end
  end

  # ── AN ENVELOPE WITH BOTH KINDS OF HISTORY ────────────────────────────────────────────────
  # THE SHAPE THE PLAN'S FIXTURE COULD NOT SHOW, and the one every real envelope has. The chain
  # above is movement-only, so its balance is entirely movement-derived and the defect this block
  # exists for is invisible in it: a destroyed pool's CATEGORIES were nullified, its entries then
  # matched `COALESCE(entries.pool_id, categories.pool_id)` for no pool at all, and the lifetime
  # spending simply left the ledger.
  #
  # Modelled on the demo's Household Supplies, where it was found: $120 in by movement, $45 out by
  # expense entries, balance $75. TWO planted literals now, and the bank balance is the difference
  # between them — $500 paid in less $45 spent — which is what `Σ pools` has to equal.
  describe "an envelope with both movement and entry history" do
    def spending = 45

    let(:supplies) { create(:pool, :budget_pool, user: user, account: checking, name: "Supplies") }
    let!(:allocation) do
      create(:pool_movement, from_pool: checking, to_pool: supplies, amount: 120, kind: :allocation)
    end
    let!(:supplies_category) do
      create(:category, :expense, user: user, pool: supplies, name: "Supplies Spending")
    end
    let!(:spend) do
      create(:entry, item: create(:item, category: supplies_category), amount: spending, date: Date.current)
    end

    before { pay(checking, deposit, named: "Salary") }

    it "starts from the figures the fixture planted", :aggregate_failures do
      expect(balance(supplies)).to eq(75) # 120 moved in, 45 spent out
      expect(balance(checking)).to eq(380) # 500 paid in, 120 moved out
      expect(total_of(checking)).to eq(deposit - spending) # 455, the bank balance
    end

    # The whole point of the fix round: 75, not 120. The movement half alone would raise the
    # buffer by the allocation and leave the spending counted nowhere.
    it "raises the buffer by the pool's balance, not by its movements alone", :aggregate_failures do
      expect(balance(checking)).to eq(380)
      expect(balance(supplies)).to eq(75)

      supplies.destroy

      expect(balance(checking)).to eq(455) # 380 + exactly 75
      expect(balance(checking)).to be_a(BigDecimal)
    end

    it "keeps Σ pools at the bank balance, to the penny", :aggregate_failures do
      expect(total_of(checking)).to eq(deposit - spending)

      supplies.destroy

      expect(total_of(checking)).to eq(deposit - spending)
      expect(total_of(checking)).to be_a(BigDecimal)
    end

    # The row, not its effect. A balance assertion is satisfied by a ledger that destroyed the
    # category and re-invented the $45 somewhere else.
    it "re-points the category to the account instead of nullifying it", :aggregate_failures do
      expect { supplies.destroy }.not_to change(Category, :count)

      expect(supplies_category.reload.pool).to eq(checking)
      expect(supplies_category.name).to eq("Supplies Spending")
      expect(spend.reload.effective_pool).to eq(checking)
    end

    it "leaves the entry itself untouched", :aggregate_failures do
      expect { supplies.destroy }.not_to change(Entry, :count)

      expect(spend.reload.amount).to eq(spending)
      expect(spend.pool).to be_nil # it never overrode; it resolves through the category
    end

    # The movement half still behaves as the chain block pins it — asserted here too because this
    # is the fixture where the two halves have to agree about the same $75.
    it "still collapses the allocation that funded it" do
      expect { supplies.destroy }.to change { PoolMovement.exists?(allocation.id) }.from(true).to(false)
    end
  end

  # A sweep runs envelope → account and an allocation runs account → envelope, so BOTH of a
  # distribution's own row kinds collapse when the envelope is destroyed. The sweep is asserted
  # separately because it is the direction the allocation example cannot reach.
  describe "a sweep back into the pool's own account" do
    let(:envelope) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
    let!(:sweep) { create(:pool_movement, from_pool: envelope, to_pool: checking, amount: 85, kind: :sweep) }

    before { pay(checking, deposit, named: "Salary") }

    it "collapses and is destroyed, leaving the buffer where it was", :aggregate_failures do
      expect(balance(checking)).to eq(585) # 500 paid in, 85 swept back
      expect(balance(envelope)).to eq(-85)

      envelope.destroy

      expect(PoolMovement.exists?(sweep.id)).to be(false)
      expect(balance(checking)).to eq(500) # 585 less the envelope's own -85
      expect(total_of(checking)).to eq(deposit)
    end
  end

  # ── THE TWO GUARDS, EACH IN BOTH DIRECTIONS ───────────────────────────────────────────────
  describe "an account" do
    let!(:envelope) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
    let!(:movement) { create(:pool_movement, from_pool: checking, to_pool: envelope, amount: 100) }

    before { pay(checking, deposit, named: "Salary") }

    it "still refuses to be destroyed while pools sit inside it", :aggregate_failures do
      expect(checking.destroy).to be(false)

      expect(checking.errors[:base]).to be_present
      expect(described_class.exists?(checking.id)).to be(true)
      expect(described_class.exists?(envelope.id)).to be(true)
      expect(PoolMovement.exists?(movement.id)).to be(true)
      expect(balance(envelope)).to eq(100)
    end

    it "is destroyed once nothing sits inside it, which is the other direction of the same rule" do
      empty = create(:pool, :account, user: user, name: "Ally")

      expect { empty.destroy }.to change { described_class.exists?(empty.id) }.from(true).to(false)
    end
  end

  # Savings pools may still be account-less until Plan 3's backfill, so an orphan's movements
  # have to land in the COUNTERPARTY's account — and when the counterparty names none either,
  # there is nowhere in the tree for the row to go.
  describe "an account-less pool" do
    let(:orphan) { create(:pool, user: user, name: "Old Vacation Fund", account: nil) }

    it "re-points its transfers into the counterparty's account", :aggregate_failures do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Car")
      transfer = create(:pool_movement, from_pool: orphan, to_pool: envelope, amount: 75)
      pay(checking, deposit, named: "Salary")

      expect(orphan.destroy).to be_truthy

      expect(transfer.reload.from_pool).to eq(checking)
      expect(transfer.to_pool).to eq(envelope)
      expect(balance(envelope)).to eq(75)
      expect(balance(checking)).to eq(425) # 500 paid in, 75 now leaving the buffer instead
    end

    it "refuses when its transfers name no account anywhere", :aggregate_failures do
      other_orphan = create(:pool, user: user, name: "Old Rainy Day Fund", account: nil)
      transfer = create(:pool_movement, from_pool: orphan, to_pool: other_orphan, amount: 75)

      expect(orphan.destroy).to be(false)

      expect(orphan.errors[:base]).to include(a_string_matching(/no buffer for its money to return to/))
      expect(described_class.exists?(orphan.id)).to be(true)
      expect(transfer.reload.from_pool).to eq(orphan)
      expect(transfer.to_pool).to eq(other_orphan)
    end

    it "is destroyed without ceremony when it holds no movements and no categories" do
      expect { orphan.destroy }.to change { described_class.exists?(orphan.id) }.from(true).to(false)
    end

    # Nullifying is the `Σ pools` break the fix round refused, so the destroy is refused instead.
    # The counterpart reach is the "both movement and entry history" block above, where an account
    # exists and the category re-points into it.
    it "refuses when categories point at it and no account can take them", :aggregate_failures do
      category = create(:category, :expense, user: user, pool: orphan, name: "Old Fund Spending")
      create(:entry, item: create(:item, category: category), amount: 30, date: Date.current)

      expect(orphan.destroy).to be(false)

      expect(orphan.errors[:base]).to include(a_string_matching(/Assign it to an account first/))
      expect(described_class.exists?(orphan.id)).to be(true)
      expect(category.reload.pool).to eq(orphan)
    end

    # THIS EXAMPLE DOES NOT DISCRIMINATE THE WRITE ORDERING, and it is written down rather than
    # claimed otherwise — the same honesty the `categories.reset` note in `Pool` carries.
    #
    # An INTERLEAVED implementation (movement loop first, refusal after) would `update!` the
    # transfer and then `throw(:abort)`, and `destroy`'s own transaction would unwind the write, so
    # every `reload` below passes under either ordering. What it does pin is the OUTCOME — a pool
    # holding both an absorbable transfer and an unabsorbable category is refused whole, with
    # nothing left half-moved — which is worth pinning on its own.
    #
    # The ordering is still the right one, for a reason no example here can reach: inside an
    # already-open JOINABLE transaction `ActiveRecord::Rollback` is swallowed and the outer
    # transaction commits, so an interleaved implementation would leave the transfer re-pointed
    # beside a pool that still exists. Reproducing that would mean committing a real outer
    # transaction from a spec that runs inside one; the reason lives in
    # `Pool#return_holdings_to_the_account`'s comment instead of in a fixture that would have to
    # fight the test harness to exist.
    it "refuses whole when its transfers could move but its categories could not", :aggregate_failures do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Car")
      transfer = create(:pool_movement, from_pool: orphan, to_pool: envelope, amount: 75)
      category = create(:category, :expense, user: user, pool: orphan, name: "Old Fund Spending")

      expect(orphan.destroy).to be(false)

      expect(transfer.reload.from_pool).to eq(orphan)
      expect(category.reload.pool).to eq(orphan)
      expect(described_class.exists?(orphan.id)).to be(true)
    end
  end

  # ── ONE TRANSACTION ───────────────────────────────────────────────────────────────────────
  # A row that was already invalid before the destroy — here a movement naming a stranger's
  # entry as its cause, which is exactly the hole Task 2's `source_entry` validation closed and
  # therefore exactly the shape an older row can be in. The re-point runs `update!`, so it
  # raises; nothing may have moved by the time it does.
  describe "when one re-point cannot be saved" do
    let(:envelope_b) { create(:pool, :budget_pool, user: user, account: checking, name: "B") }
    let(:envelope_c) { create(:pool, :budget_pool, user: user, account: checking, name: "C") }
    let!(:allocation) do
      create(:pool_movement, from_pool: checking, to_pool: envelope_b, amount: 100, kind: :allocation)
    end
    let!(:transfer) do
      create(:pool_movement, from_pool: envelope_b, to_pool: envelope_c, amount: 60, kind: :transfer)
    end

    before do
      pay(checking, deposit, named: "Salary")
      # The point of the fixture: a row that is already invalid on disk, which is what a
      # validation added after the data (Task 2's `source_entry` ownership guard) leaves behind.
      # `update!` cannot plant it, so the write has to skip the model.
      # rubocop:disable Rails/SkipsModelValidations
      transfer.update_column(:source_entry_id, create(:entry, :income).id)
      # rubocop:enable Rails/SkipsModelValidations
    end

    it "raises and writes nothing at all", :aggregate_failures do
      expect { envelope_b.destroy }.to raise_error(ActiveRecord::RecordInvalid)

      expect(described_class.exists?(envelope_b.id)).to be(true)
      expect(PoolMovement.exists?(allocation.id)).to be(true)
      expect(transfer.reload.from_pool).to eq(envelope_b)
      expect(allocation.reload.to_pool).to eq(envelope_b)
      expect(balance(envelope_b)).to eq(40)
      expect(balance(checking)).to eq(400)
      expect(total_of(checking)).to eq(deposit)
    end
  end

  # ── THE CROSS-CHECK AGAINST DISTRIBUTION REPLACEMENT ──────────────────────────────────────
  # `AllocationCommitter#previous_distribution` filters on `distributed` AND the period AND the
  # ACCOUNT as an endpoint. A re-pointed row now has the account on one end, so the question is
  # whether replacing this period's split can reach it: it cannot, because the only rows that
  # SURVIVE re-pointing are transfers (an allocation and a sweep both collapse), and `distributed`
  # selects neither. Measured rather than argued.
  describe "replacing this period's distribution after an envelope was destroyed" do
    let(:user) { create(:user, :biweekly) }
    let(:today) { Date.new(2026, 8, 20) }
    let(:this_period) { Date.new(2026, 8, 15) }
    let(:envelope_b) { create(:pool, :budget_pool, user: user, account: checking, name: "B") }
    let(:envelope_c) { create(:pool, :budget_pool, user: user, account: checking, name: "C") }
    let!(:allocation) do
      create(
        :pool_movement,
        from_pool: checking,
        to_pool: envelope_b,
        amount: 100,
        kind: :allocation,
        date: this_period
      )
    end
    let!(:transfer) do
      create(
        :pool_movement,
        from_pool: envelope_b,
        to_pool: envelope_c,
        amount: 60,
        kind: :transfer,
        date: this_period
      )
    end

    before do
      create(:pool_budget, :per_paycheck_rate, pool: envelope_c, amount: 200)
      pay(checking, deposit, named: "Salary", on: this_period)
      envelope_b.destroy
    end

    def redistribute
      AllocationCommitter.new(
        AllocationCalculator.new(user: user, account: checking, today: today)
      ).call
    end

    it "neither raises nor takes the re-pointed transfer with it", :aggregate_failures do
      expect(transfer.reload.from_pool).to eq(checking)

      result = nil
      expect { result = redistribute }.not_to raise_error

      expect(result.errors).to be_empty
      expect(PoolMovement.exists?(allocation.id)).to be(false) # collapsed by the destroy, not by the replacement
      expect(PoolMovement.exists?(transfer.id)).to be(true)
      expect(transfer.reload.from_pool).to eq(checking)
      expect(transfer.to_pool).to eq(envelope_c)
      expect(transfer.kind).to eq("transfer")
    end

    it "leaves Σ pools equal to the money that was paid in, across both writes", :aggregate_failures do
      expect(total_of(checking)).to eq(deposit)

      redistribute

      expect(total_of(checking)).to eq(deposit)
    end
  end
end
