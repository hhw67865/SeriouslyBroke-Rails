# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category, optional: true, touch: true
  belongs_to :pool, optional: true, touch: true
  belongs_to :item, optional: true

  enum :basis, { monthly: 0, per_paycheck: 1 }, prefix: true

  validates :amount, presence: true
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  validate :exactly_one_owner
  validate :category_must_be_expense, if: :category_mode?
  validate :category_must_not_have_pool, if: :category_mode?
  validate :pool_must_not_be_an_account, if: :pool_mode?
  validate :shape_must_be_valid, if: :pool_mode?
  validate :item_must_belong_to_pool, if: :pool_mode?
  validate :item_must_not_be_claimed, if: :pool_mode?

  # An assigned-but-unsaved association has no foreign key yet, so consult the
  # target too — otherwise `Budget.new(pool: unsaved_pool)` reads as owner-less.
  def category_mode? = category_id.present? || category.present?
  def pool_mode? = pool_id.present? || pool.present?

  def user = category_mode? ? category.user : pool.user

  def calculator(today: Date.current)
    BudgetCalculator.new(self, today: today)
  end

  private

  def exactly_one_owner
    errors.add(:base, "must belong to either a category or a pool") if !category_mode? && !pool_mode?
    errors.add(:base, "cannot belong to both a category and a pool") if category_mode? && pool_mode?
  end

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def category_must_not_have_pool
    errors.add(:category, "cannot have a budget when linked to a savings pool") if category&.pool_id?
  end

  def pool_must_not_be_an_account
    errors.add(:pool, "cannot be an account") if pool&.pool_type_account?
  end

  # See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §3.1
  def shape_must_be_valid
    if basis_per_paycheck?
      errors.add(:basis, "per-paycheck rules cannot have a due date or interval") if anchor_date.present? || interval_months.present?
      return
    end

    return if anchor_date.present?

    errors.add(:interval_months, "is required for a monthly rule with no due date") if interval_months.blank?
  end

  def item_must_belong_to_pool
    return if item.blank?

    errors.add(:item, "must belong to a category in this pool") unless item.category&.pool_id == pool_id
  end

  # `where.not(id: nil)` renders as `id IS NOT NULL`, so an unsaved budget still
  # compares against every persisted rule. An unsaved *item* has no id though,
  # and `item_id: nil` would match every item-less budget — bail rather than
  # invent a conflict.
  def item_must_not_be_claimed
    return if item&.id.blank?

    claimed = Budget.where(item_id: item.id).where.not(id: id).exists?
    errors.add(:item, "is already used by another rule") if claimed
  end
end
