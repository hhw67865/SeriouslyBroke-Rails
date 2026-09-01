# frozen_string_literal: true

# THE PURPOSE LEDGER'S ONLY WRITER BESIDES ENTRIES (two-ledger spec §2). A side is a category or
# NULL, and NULL means AVAILABLE — the root every allocation ultimately draws on. No account
# ever appears here: allocating money is an act of intention, not location, so it moves
# nothing physical. Kinds keep the distribution vocabulary (`allocation`/`sweep` are what a
# distribution writes and may replace; `transfer` is a hand move).
class Allocation < ApplicationRecord
  belongs_to :from_category, class_name: "Category", optional: true, touch: true
  belongs_to :to_category, class_name: "Category", optional: true, touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  enum :kind, { transfer: 0, allocation: 1, sweep: 2 }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :sides_must_differ
  validate :sides_must_be_expense_categories_of_one_user

  scope :for_entry, ->(entry) { where(source_entry: entry) }
  scope :distributed, -> { where(kind: [:allocation, :sweep]) }

  def user = (from_category || to_category)&.user

  private

  def sides_must_differ
    return unless from_category_id.present? && from_category_id == to_category_id

    errors.add(:to_category, "must differ from the source")
  end

  def sides_must_be_expense_categories_of_one_user
    sides = [from_category, to_category].compact
    return errors.add(:base, "needs at least one category") if sides.empty?
    return errors.add(:base, "must stay within one user") if sides.map(&:user).uniq.size > 1

    errors.add(:base, "only expense categories hold money") unless sides.all?(&:expense?)
  end
end
