# frozen_string_literal: true

# A TRANSFER BETWEEN TWO OF ONE USER'S OWN BANK ACCOUNTS, and after the drop (two-ledger spec §5)
# that is the only thing this table holds. Net worth is unchanged: money entering or leaving the
# user's life is an `Entry`, and money changing PURPOSE without moving is an `Allocation`.
#
# WHAT THE RENAME DELETED ALONG WITH THE WORD "POOL":
#
#   * `kind`'s `allocation` and `sweep` members. They existed so a distribution could find and
#     replace its own rows; a distribution writes `allocations` now and marks them there
#     (`Allocation.distributed`). One member is left and `account_movements_are_transfers` holds it
#     at the database, past the model — so the column is kept rather than dropped for the reason
#     `Pool#pool_type` is kept: a live CHECK and a live enum saying one thing beats a column
#     silently meaning it.
#   * `#crosses_accounts?` and `#must_not_cross_accounts`. Both ends of every row are accounts now,
#     so "does this cross an account boundary" is true of every movement there is — the question
#     had content only while a pool could sit INSIDE an account.
#   * `#source_must_hold_it` and the `:reallocation` context it was validated on. Reallocation
#     moved to the purpose ledger in Task 4 and `Allocation#source_must_hold_it` is that rule where
#     it now costs money; this one asked `PoolCalculator` for a balance and had no caller left.
#
# `source_entry` STAYS, and it is the routing link rather than a distribution's: an income entry
# that landed somewhere other than main is mirrored by ONE transfer main → there, and
# `Entry#route_income_to!` finds it again by this column.
class AccountMovement < ApplicationRecord
  belongs_to :from_pool, class_name: "Pool", touch: true
  belongs_to :to_pool, class_name: "Pool", touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  enum :kind, { transfer: 0 }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :accounts_must_differ
  validate :accounts_must_share_a_user
  validate :source_entry_must_share_the_user

  scope :for_entry, ->(entry) { where(source_entry: entry) }

  delegate :user, to: :from_pool

  private

  def accounts_must_differ
    return if from_pool.blank? || to_pool.blank?

    errors.add(:to_pool, "must differ from the source account") if from_pool == to_pool
  end

  # Two accounts that name no user at all compare `nil == nil` and read as sharing an owner,
  # so an absent user is rejected outright rather than matched against another absent one.
  def accounts_must_share_a_user
    return if from_pool.blank? || to_pool.blank?

    owner = from_pool.user
    errors.add(:to_pool, "must belong to the same user") if owner.blank? || owner != to_pool.user
  end

  # SPEC §7a — the third ownership edge on this table, and the one that had no guard.
  #
  # `source_entry` is a bare foreign key to `entries` with no user on it. Nothing but this stopped a
  # movement between MY accounts from naming SOMEONE ELSE'S paycheck as its cause: the money would
  # move correctly — the physical partition still equals bank truth, so the invariant would never
  # notice — while `Entry#routed_account` answered about a stranger's deposit.
  #
  # Compared against `from_pool.user` alone because #accounts_must_share_a_user already refuses a
  # movement whose two ends disagree, so one end is the whole answer; checking both would report the
  # same defect twice under a different name.
  #
  # Records, not ids, for the reason every guard on this class uses records: under `build` nothing
  # is persisted and every id is nil, so `nil == nil` waves a foreign entry through. An entry that
  # names no user at all is rejected outright rather than matched against an account that names none
  # either — the same both-nil hole #accounts_must_share_a_user closes.
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
