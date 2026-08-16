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

  # Two pools that name no user at all compare `nil == nil` and read as sharing an owner,
  # so an absent user is rejected outright rather than matched against another absent one.
  def pools_must_share_a_user
    return if from_pool.blank? || to_pool.blank?

    owner = from_pool.user
    errors.add(:to_pool, "must belong to the same user") if owner.blank? || owner != to_pool.user
  end
end
