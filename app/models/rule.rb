# frozen_string_literal: true

class Rule < ApplicationRecord
  belongs_to :category, touch: true
  belongs_to :item, optional: true
  has_many :adjustments, as: :source, dependent: :destroy

  enum :rule_type, { bill: 0, usage: 1, choice: 2 }

  # The give-way order: a choice gives way first, a bill last.
  TYPE_RANK = { choice: 0, usage: 1, bill: 2 }.freeze
  CATCH_ALL_TAKEN = "this category already has a rule covering all of its spending — change that " \
                    "one instead, or point this rule at a single item"
  NEVER_DUE = Date.new(9999, 12, 31)

  scope :for_user, ->(user) { where(category_id: user.categories.select(:id)) }
  scope :dated, -> { where.not(anchor_date: nil) }
  scope :per_period, -> { where(anchor_date: nil) }
  scope :saving_toward_a_date, -> { dated.where(item_id: nil, interval_months: nil).where.not(rule_type: :bill) }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :starts_on, presence: true
  validates :rule_type, presence: true
  validates :interval_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :cap, numericality: { greater_than: 0 }, allow_nil: true
  validate :category_is_an_expense
  validate :item_is_in_the_category
  validate :one_item_less_rule_per_category
  validate :item_has_one_rule
  validate :keeping_never_dates
  validate :interval_needs_a_date
  validate :cap_needs_a_fund

  delegate :user, to: :category

  # Dated rules first, soonest first, then the largest amount.
  def self.sort_key(next_due_on:, amount:, id:)
    [next_due_on.present? ? 0 : 1, next_due_on || NEVER_DUE, -amount.to_d, id]
  end

  delegate :today, to: :user

  def type_rank = TYPE_RANK.fetch(rule_type.to_sym)

  def claim_calculator(today: self.today, spending: nil, adjustments: nil)
    ClaimCalculator.new(self, today: today, spending: spending, adjustments: adjustments)
  end

  # The one door onto the entries behind this rule's figure.
  def counted_entries(today: user.today) = claim_calculator(today: today).counted_entries

  def shape
    return :dated if anchor_date.present?

    keeps_unspent? ? :fund : :rate
  end

  def cadence
    return :per_period if anchor_date.blank?

    interval_months.blank? ? :one_off : :every_n
  end

  def saving_toward_a_date? = item_id.nil? && anchor_date.present? && interval_months.nil? && !bill?

  def capped? = cap.present?

  # What the rule costs each period: its amount, a one-off target spread to its date, or a rolling
  # amount spread over the interval on the user's grid.
  def ask(today: self.today)
    case cadence
    when :per_period then amount.to_d
    when :one_off then claim_calculator(today: today).ask
    else (amount.to_d * 12 / (user.periods_per_year * interval_months)).round(2)
    end
  end

  private

  def category_is_an_expense
    errors.add(:category, "must be an expense category") if category&.income?
  end

  def item_is_in_the_category
    return if item.blank? || category.blank?

    errors.add(:item, "must belong to this category") unless item.category_id == category.id
  end

  def one_item_less_rule_per_category
    return if item_id.present? || category_id.blank?

    errors.add(:base, CATCH_ALL_TAKEN) if Rule.where(category_id: category_id, item_id: nil).where.not(id: id).exists?
  end

  def item_has_one_rule
    return if item_id.blank?

    errors.add(:item, "is already used by another rule") if Rule.where(item_id: item_id).where.not(id: id).exists?
  end

  def keeping_never_dates
    return unless keeps_unspent? && anchor_date.present?

    errors.add(:anchor_date, "cannot be set on a rule that keeps what it doesn't spend")
  end

  def interval_needs_a_date
    return unless interval_months.present? && anchor_date.blank?

    errors.add(:interval_months, "needs a due date to count from")
  end

  def cap_needs_a_fund
    return unless cap.present? && !keeps_unspent?

    errors.add(:cap, "only a rule that keeps what it doesn't spend can have a cap")
  end
end
