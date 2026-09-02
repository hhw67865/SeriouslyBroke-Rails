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
    #
    # THE MAIN-ACCOUNT DIRECTION of B2's pair (main-account spec §6, fix round 2): `checking` is
    # both `supplies.account` and `user.default_account` here, so this example does not
    # discriminate between the two possible destinations — "an envelope in a non-main account"
    # below is the fixture that does, and is the one the production 500 needed.
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

  # B2 (main-account spec §6, fix round 2) — THE PRODUCTION 500 THE REVIEWER REPRODUCED.
  # `#hand_categories_to_the_account` used to re-point a category to THIS pool's own account,
  # which is illegal the instant that account is not the user's main one:
  # `Category#pool_must_be_reachable` refuses it, `update!` raises `ActiveRecord::RecordInvalid`,
  # and `PoolsController#destroy` has no rescue for it — deleting an ordinary envelope 500'd for
  # any user whose envelope lived in a second account. The destination is now always
  # `user.default_account`, and this is the direction the block above cannot exercise (there,
  # the envelope's own account and main happen to be the same pool).
  describe "an envelope in a non-main account" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }
    let(:side_gig) { create(:pool, :budget_pool, user: user, account: ally, name: "Side Gig") }
    let!(:spending) { create(:category, :expense, user: user, pool: side_gig, name: "Side Gig Spending") }
    let!(:spend) { create(:entry, item: create(:item, category: spending), amount: 80, date: Date.current) }

    before { user.update!(default_account: checking) }

    it "re-points the category to the user's main account rather than raising", :aggregate_failures do
      expect { side_gig.destroy }.not_to raise_error

      expect(spending.reload.pool).to eq(checking)
      expect(spend.reload.effective_pool).to eq(checking)
    end

    # THE SPLIT `Pool#hand_categories_to_the_account`'s own comment names, pinned rather than
    # left to prose: Ally never held this category's spending (it lived in the envelope alone,
    # and no movement ever touched Ally directly in this fixture), so Ally's own balance is
    # untouched by the destroy — the $80 moves onto Checking, main, and nowhere else.
    it "moves the category's balance onto main, not onto the envelope's own account", :aggregate_failures do
      expect(balance(ally)).to eq(0)
      expect(balance(side_gig)).to eq(-80)

      side_gig.destroy

      expect(balance(ally)).to eq(0)
      expect(balance(checking)).to eq(-80)
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

  # ── THE ACCOUNT-LESS POOL BLOCK IS DELETED, AND THE SHAPE WITH IT (plan 3, task 6) ────────
  #
  # Five examples stood here, all planted on `create(:pool, account: nil)`: an orphan's transfers
  # re-pointed into the COUNTERPARTY's account, the refusal when the counterparty named none
  # either, the refusal when categories pointed at it, and the two quiet directions. Their opening
  # comment began "Savings pools may still be account-less until Plan 3's backfill" — and the
  # backfill has landed. `Pool#account_matches_pool_type` refuses an account-less envelope or goal
  # and `CHECK ((pool_type = 0) = (account_id IS NULL))` refuses it again past the model, so the
  # fixture cannot be built by any writer this app or this suite has.
  #
  # The guards they covered — `Pool::REFUSALS`, `#refuse_for_want_of_an_account`,
  # `#absorbing_account_for`'s counterparty fallback — are KEPT and are now unreachable backstops.
  # That is written down rather than dressed up: re-planting the fixture by clearing `account` in
  # memory before `destroy` (which skips validations) would make every example pass again while
  # testing a shape no caller produces, and a fake test is worse than an acknowledged gap. The
  # deletion of the orphan apparatus — these guards, `HomePresenter#orphan_pools` and its
  # attention band, `BudgetPagePresenter#orphan_rules`, `PoolReallocationPresenter`'s "No account"
  # group — is the follow-up this tightening creates, and it is larger than the task that created
  # it.
  #
  # What replaces them is the destroy this task DID make reachable: an account whose categories
  # still point at it.

  # ── THE THIRD GUARD, BOTH DIRECTIONS (plan 3, task 6) ─────────────────────────────────────
  # `has_many :categories` was `dependent: :nullify`, which reached `update_all` and wrote NULL
  # `pool_id`s past the required `belongs_to` — every entry those categories carried leaving the
  # pool tree, `Σ pools` rising by the account's lifetime spending. An ENVELOPE never reached it
  # (`#return_holdings_to_the_account` re-points first, and the block above pins that); an ACCOUNT
  # returns from that callback on its first line, so the account was the one case it ever ran in.
  describe "an account whose categories still point at it" do
    let!(:spending) { create(:category, :expense, user: user, pool: checking, name: "Bank Fees") }

    before { pay(checking, deposit, named: "Salary") }

    it "refuses, and writes nothing", :aggregate_failures do
      expect(checking.destroy).to be(false)

      expect(checking.errors[:base]).to be_present
      expect(described_class.exists?(checking.id)).to be(true)
      expect(spending.reload.pool).to eq(checking)
    end

    # THE ASSERTION THAT DISCRIMINATES THE OLD BEHAVIOUR FROM THE NEW, and it is the data rather
    # than the flash: `dependent: :nullify` returned TRUE from this destroy and left the category
    # pointing at nothing. Both halves are pinned because the refusal alone would pass against a
    # nullify that happened to fail for some other reason.
    it "leaves the category resolving to a pool, which nullify did not" do
      checking.destroy

      expect(spending.reload.pool_id).not_to be_nil
    end

    # EVERY category, not just the expense one: `#pay` gives this account an income category too,
    # and an account a real user owns always has both. Moving one and not the other is the state
    # the refusal is for.
    #
    # Reached through `user.categories` RATHER THAN `checking.categories`, and the difference is
    # the behaviour: `restrict_with_error` asks `#empty?`, which trusts a LOADED target over the
    # database, so re-pointing through the pool's own association and then destroying refuses a
    # pool that has nothing left pointing at it. That is why `#hand_categories_to_the_account`
    # ends in a `reset` — a line whose comment used to say it fired against nothing.
    it "is destroyed once its categories point somewhere else, the other direction of the rule" do
      second = create(:pool, :account, user: user, name: "Ally")
      # I4+B1 sweep (main-account spec §6): a category may only point at the user's MAIN account
      # or an envelope, so "somewhere else" for an account-pointed category has to be the new
      # main — `second` takes over the role before the re-point, the same as a real user naming
      # a different account primary.
      user.update!(default_account: second)
      user.categories.each { |category| category.update!(pool: second) }

      expect { checking.destroy }.to change { described_class.exists?(checking.id) }.from(true).to(false)
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
  # ITS ANSWER GOT STRONGER WITH THE TWO-LEDGER CUTOVER, and the example is kept for exactly that.
  # `AllocationCommitter#previous_distribution` used to filter `pool_movements` on `distributed` AND
  # the period AND the ACCOUNT as an endpoint, so "can replacing this period's split reach a
  # re-pointed row" was a question about three filters. It now reads `allocations` — a different
  # table entirely — so a `pool_movements` row cannot be reached by a replacement at all, whatever
  # its kind or its ends. What is pinned below is that the destroy and the redistribution coexist:
  # the destroy collapses what it collapses, the split writes what it writes, and neither touches
  # the other's rows. Measured rather than argued.
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
      create(:pool_budget, :per_period_rate, pool: envelope_c, amount: 200)
      pay(checking, deposit, named: "Salary", on: this_period)
      envelope_b.destroy
    end

    def redistribute
      AllocationCommitter.new(AllocationCalculator.new(user: user, today: today)).call
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
