# frozen_string_literal: true

# A transfer of money between two of a user's own pools. Net worth is unchanged.
# Money entering or leaving the user's life is an Entry, never a PoolMovement.
class PoolMovement < ApplicationRecord
  belongs_to :from_pool, class_name: "Pool", touch: true
  belongs_to :to_pool, class_name: "Pool", touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :pools_must_differ
  validate :pools_must_share_a_user

  scope :for_entry, ->(entry) { where(source_entry: entry) }

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

  def pools_must_share_a_user
    return if from_pool.blank? || to_pool.blank?

    errors.add(:to_pool, "must belong to the same user") unless from_pool.user == to_pool.user
  end
end
