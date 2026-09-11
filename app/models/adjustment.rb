# frozen_string_literal: true

# A signed delta on one claim source's accrual, dated inside a period it counts. The source is a
# rule or a savings account; an account only ever reduces, since with no ceiling saving more is
# just transferring more.
class Adjustment < ApplicationRecord
  belongs_to :source, polymorphic: true, touch: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validate :accounts_only_reduce

  scope :dated_within, ->(range) { where(date: range) }
  scope :on_rules, ->(ids) { where(source_type: "Rule", source_id: ids) }
  scope :on_accounts, ->(ids) { where(source_type: "Account", source_id: ids) }

  delegate :user, to: :source

  def rule? = source_type == "Rule"
  def account? = source_type == "Account"

  private

  def accounts_only_reduce
    return unless account? && amount.to_d.positive?

    errors.add(:amount, "can only reduce what savings is owed")
  end
end
