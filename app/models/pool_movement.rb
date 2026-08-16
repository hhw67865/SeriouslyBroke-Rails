# frozen_string_literal: true

# A transfer of money between two of a user's own pools. Net worth is unchanged.
# Money entering or leaving the user's life is an Entry, never a PoolMovement.
class PoolMovement < ApplicationRecord
  belongs_to :from_pool, class_name: "Pool", touch: true
  belongs_to :to_pool, class_name: "Pool", touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  # What wrote this row, and it exists so a distribution can be REPLACED. Nothing else on
  # the table distinguishes a distribution's allocation from a sweep or from a manual
  # reallocation, so "redo this period's split" would otherwise have to delete by date and
  # would take the user's own reallocations with it.
  #
  # `transfer` is 0, so it is the column default: every row written by any other path — the
  # entry-driven movements, Task 7's reallocation screen — is a transfer without saying so,
  # and replacement cannot see it.
  #
  # Prefixed, because `movement.transfer?` on a class whose entire purpose is transferring
  # money reads as "is this a movement" rather than "is this NOT part of a distribution".
  enum :kind, { transfer: 0, allocation: 1, sweep: 2 }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :pools_must_differ
  validate :pools_must_share_a_user
  validate :source_entry_must_share_the_user

  # SPEC §5 PUTS CROSS-ACCOUNT TRANSFERS OUT OF SCOPE, and this is where that scope is enforced
  # for the one path that has to honour it: Task 7's reallocation screen, which saves on the
  # `:reallocation` context.
  #
  # On a context rather than unconditionally, because the model deliberately supports the
  # movement it refuses here — "model support exists, UI deferred" is the spec's own wording, and
  # #crosses_accounts? exists to answer the question rather than to forbid the answer. Making it
  # a plain validation would retire that support and take the entry-driven movements with it.
  #
  # Here rather than in the controller so the constraint and the reader that expresses it live
  # together: ReallocationPresenter builds its source list by asking every candidate movement the
  # same #crosses_accounts?, so a pool the screen refuses to offer is a pool the save refuses to
  # write, by one method rather than by two that agree today.
  validate :must_not_cross_accounts, on: :reallocation

  # THE FLOOR THE REALLOCATION SCREEN IS BUILT AROUND, ENFORCED WHERE IT COSTS MONEY.
  #
  # That screen disables a source that does not hold the amount — but a disabled control is a
  # RENDERING, and this is the write. A tab rendered while Car held $1,000 and submitted after Car
  # was spent down, or a hand-edited `from_pool_id`, would otherwise write the move and leave the
  # source overdrawn: `Σ pools` would still equal the bank balance, but one envelope would be
  # holding money the app had already spent, which is the state the whole screen exists to avoid
  # creating on purpose.
  #
  # Ownership is mirrored at the write (the controller's scoped lookup) and so is same-account
  # (above); this was the one constraint the screen was built around that lived only in the view.
  #
  # `:reallocation`-only, for #must_not_cross_accounts' reason and one more: an ALLOCATION legally
  # empties the account it comes from, and a SWEEP is derived from the source's own balance, so a
  # blanket version of this would put a live balance query in front of every movement a
  # distribution writes to re-answer a question those paths have already answered.
  validate :source_must_hold_it, on: :reallocation

  scope :for_entry, ->(entry) { where(source_entry: entry) }

  # The two kinds a distribution writes, and the only two it may delete when it replaces
  # itself. Named here rather than spelled out in AllocationCommitter so "what a distribution
  # consists of" has one home — Task 7 needs the same fact to stay out of the way.
  scope :distributed, -> { where(kind: [:allocation, :sweep]) }

  delegate :user, to: :from_pool

  # True when the money has to physically move between real bank accounts.
  def crosses_accounts?
    containing_account(from_pool) != containing_account(to_pool)
  end

  private

  # An account pool sits inside no other account: it stands in as its own. That is what
  # keeps Checking -> Groceries (a pool inside Checking) from reading as a bank transfer.
  # Compared as records rather than ids, so unsaved pools are not all equal on a nil id.
  def containing_account(pool)
    pool.account || pool
  end

  def pools_must_differ
    return if from_pool.blank? || to_pool.blank?

    errors.add(:to_pool, "must differ from the source pool") if from_pool == to_pool
  end

  # Both ends must be present before the question means anything: `containing_account(nil)` is a
  # NoMethodError, and a movement missing an end already fails `belongs_to`'s own presence check.
  def must_not_cross_accounts
    return if from_pool.blank? || to_pool.blank?

    errors.add(:to_pool, "must be in the same account — moving money between accounts isn't supported yet") if
      crosses_accounts?
  end

  # A FRESH calculator, deliberately: the question is what the source holds at the instant before
  # this row is inserted, which is the whole point of re-checking here rather than trusting what a
  # screen measured. PoolCalculator memoises, so anything held from the render would answer about
  # the balance that made the row look affordable in the first place.
  #
  # `balance`, not `free_amount`: what a rule has CLAIMED is a warning the screen states, not a
  # refusal (spec §4.2 — robbing one envelope to save another is the workflow). What the envelope
  # does not HOLD is the refusal.
  def source_must_hold_it
    return if from_pool.blank? || amount.blank?

    held = from_pool.calculator.balance
    return if amount <= held

    errors.add(
      :amount,
      "is more than #{from_pool.name} holds — it has #{ActiveSupport::NumberHelper.number_to_currency(held)}"
    )
  end

  # Two pools that name no user at all compare `nil == nil` and read as sharing an owner,
  # so an absent user is rejected outright rather than matched against another absent one.
  def pools_must_share_a_user
    return if from_pool.blank? || to_pool.blank?

    owner = from_pool.user
    errors.add(:to_pool, "must belong to the same user") if owner.blank? || owner != to_pool.user
  end

  # SPEC §7a — the third ownership edge on this table, and the one that had no guard.
  #
  # `source_entry` is what makes a distribution replaceable (see the `kind` enum), and the
  # column is a bare foreign key to `entries` with no user on it. Nothing but this stopped a
  # movement between MY pools from naming SOMEONE ELSE'S paycheck as its cause: the money
  # would move correctly — `Σ pools` still equals the bank balance, so the invariant would
  # never notice — while "replace this period's distribution" keyed off a stranger's entry.
  #
  # Compared against `from_pool.user` alone because #pools_must_share_a_user already refuses a
  # movement whose two ends disagree, so one end is the whole answer; checking both would
  # report the same defect twice under a different name.
  #
  # Records, not ids, for the reason every guard on this class uses records: under `build`
  # nothing is persisted and every id is nil, so `nil == nil` waves a foreign entry through.
  # An entry that names no user at all is rejected outright rather than matched against a
  # pool that names none either — the same both-nil hole #pools_must_share_a_user closes.
  def source_entry_must_share_the_user
    return if source_entry.blank? || from_pool.blank?

    owner = from_pool.user
    errors.add(:source_entry, "must belong to the same user") if owner.blank? || owner != source_entry_owner
  end

  # `Entry#user` delegates through `item` without `allow_nil`, so it raises on a half-built
  # entry. A validation must return an ANSWER for every record it is handed, including the
  # invalid ones — a NoMethodError out of `valid?` is not a rejection.
  def source_entry_owner = source_entry.item&.category&.user
end
