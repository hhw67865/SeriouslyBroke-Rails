# frozen_string_literal: true

# One promise that a savings account is owed money from checking: a fixed amount a period when it
# names no item, or a share of an income item's entries when it does. Each row counts from its
# own starts_on.
class SavingsTarget < ApplicationRecord
  belongs_to :account, touch: true
  belongs_to :item, optional: true

  before_validation :keep_one_figure
  before_validation { self.starts_on ||= account&.user&.today }

  validates :starts_on, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }, if: :target?
  validates :percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: :share?
  validates :item, presence: { message: "no longer exists" }, if: -> { item_id.present? }
  validate :account_is_savings
  validate :account_has_one_fixed_target
  validate :item_is_the_users_income
  validate :item_feeds_this_account_once
  validate :item_is_not_over_shared

  delegate :user, to: :account

  scope :fixed, -> { where(item_id: nil) }
  scope :shares, -> { where.not(item_id: nil) }

  def target? = item.nil?
  def share? = !target?

  # What this row costs a period: its amount, or its percent of what the item typically brings in.
  def ask(typical_income: nil)
    return amount.to_d if target?

    (percent.to_d / 100 * typical_income.to_d).round(2)
  end

  def words
    return "#{ActiveSupport::NumberHelper.number_to_currency(amount)} a period" if target?

    "#{percent.to_d.to_s("F").sub(/\.0+\z/, "")}% of #{item.name}"
  end

  private

  def keep_one_figure
    target? ? self.percent = nil : self.amount = nil
  end

  def account_is_savings
    errors.add(:account, "checking never carries a savings target") if account&.main?
  end

  # Siblings already held in memory (an unsaved row built alongside this one in the same form
  # submit) can collide with this row before either has touched the database, so they are checked
  # too. `#target`, never `#to_a` or `#load_target` — nested attributes builds new rows into it
  # without ever marking the association loaded, and forcing a fresh load here would cache a stale
  # (possibly empty) collection on the account for the rest of its life, hiding a row built moments
  # later through `account.savings_targets_attributes=`. Reading `#target` triggers no query at all.
  def unsaved_siblings
    return [] if account.blank?

    account.association(:savings_targets).target.reject { |t| same_record?(t) || t.marked_for_destruction? }
  end

  # `equal?` alone misses a sibling loaded from a separate query (a different Ruby object for the
  # same row); persisted rows are the same record when their ids match.
  def same_record?(other)
    persisted? ? other.id == id : other.equal?(self)
  end

  # Ids the persisted-row check must not treat as a clash: this row's own id, and any sibling
  # marked for destruction in the same save — it is still in the database until the transaction
  # commits, but it is on its way out and must not block a replacement built alongside it.
  def ids_to_ignore
    doomed = account.present? ? account.association(:savings_targets).target.select(&:marked_for_destruction?).map(&:id) : []
    ([id] + doomed).compact
  end

  def account_has_one_fixed_target
    return unless target?

    errors.add(:account, "already has a fixed target") if fixed_target_clash?
  end

  def fixed_target_clash?
    unsaved_siblings.any?(&:target?) || persisted_fixed_target_clash?
  end

  def persisted_fixed_target_clash?
    account_id.present? && SavingsTarget.where(account_id: account_id, item_id: nil).where.not(id: ids_to_ignore).exists?
  end

  def item_is_the_users_income
    return if item.blank? || account.blank?

    errors.add(:item, "must be one of your income items") unless item.user == account.user && item.category.income?
  end

  def item_feeds_this_account_once
    return if item.blank?

    errors.add(:item, "already feeds this account") if item_share_clash?
  end

  # A still-unsaved item has no item_id yet, so it has nothing to collide with in memory —
  # comparing nils would wrongly match a sibling fixed row, which also carries a nil item_id.
  def item_share_clash?
    (item_id.present? && unsaved_siblings.any? { |t| t.item_id == item_id }) || persisted_item_share_clash?
  end

  def persisted_item_share_clash?
    item.persisted? && SavingsTarget.where(account_id: account_id, item_id: item.id).where.not(id: ids_to_ignore).exists?
  end

  def item_is_not_over_shared
    return if item.blank? || percent.blank?

    taken = item.savings_shares.where.not(id: id).sum(:percent).to_d
    errors.add(:percent, "would take #{item.name} past 100% across your accounts") if taken + percent.to_d > 100
  end
end
