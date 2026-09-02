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
  validate :source_entry_must_share_the_user

  # THE FLOOR THE REALLOCATION SCREEN IS BUILT AROUND, ENFORCED WHERE IT COSTS MONEY —
  # `PoolMovement#source_must_hold_it` ported (two-ledger Task 4).
  #
  # That screen disables a source that does not hold the amount, but a disabled control is a
  # RENDERING and this is the write. A tab rendered while Car held $1,000 and submitted after Car was
  # spent down, or a hand-edited `from_category_id`, would otherwise write the move and leave the
  # source overspent: both partitions of §2's invariant would still hold, while one category held
  # money the app had already spent — the state the whole screen exists to avoid creating on purpose.
  #
  # `:reallocation`-ONLY, and the reason survives the port intact: a distribution's ALLOCATION legally
  # empties the root it comes from, and its SWEEP is derived from the source's own balance, so a
  # blanket version would put a live balance query in front of every row a distribution writes to
  # re-answer a question those paths have already answered.
  validate :source_must_hold_it, on: :reallocation

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

  # `PoolMovement#source_entry_must_share_the_user` PORTED, and it is the same hole in the same
  # shape: `source_entry_id` is a bare FK to `entries` and nothing on this table says whose entry it
  # is, so an allocation between MY categories could name a STRANGER'S paycheck as its cause. Both
  # partitions of §2's invariant would still hold — the row moves money between two of MY categories
  # whatever it claims caused it — while `AllocationCommitter`'s "replace this period's split" keyed
  # off somebody else's entry.
  #
  # THE OWNER IS `#user`, NOT `to_category.user`, because either side may be NULL: a sweep names
  # only a source, and a guard reading the destination alone would wave every sweep's entry through.
  #
  # RECORDS, NOT IDS. On a `build` nothing is persisted and every id is nil, so an id comparison
  # reads `nil == nil` and accepts the foreign entry.
  def source_entry_must_share_the_user
    return if source_entry.blank?

    owner = user
    errors.add(:source_entry, "must belong to the same user") if owner.blank? || owner != source_entry_owner
  end

  # `Entry#user` delegates through `item` without `allow_nil`, so it raises on a half-built entry. A
  # validation must return an ANSWER for every record it is handed, including the invalid ones — a
  # NoMethodError out of `valid?` is not a rejection.
  def source_entry_owner = source_entry.item&.category&.user

  # THE NULL SOURCE IS AVAILABLE and its balance is the ROOT's, which is a fact about the user rather
  # than about any category — so it is read from `CategoryLedger#available` where a category's is read
  # from its own calculator. A move out of available that available cannot cover is the same mistake
  # as one out of an empty envelope, and it is refused in the same words.
  def source_must_hold_it
    return if amount.blank? || (from_category.blank? && user.blank?)

    held = source_balance
    return if amount <= held

    errors.add(
      :amount,
      "is more than #{source_name} holds — it has #{ActiveSupport::NumberHelper.number_to_currency(held)}"
    )
  end

  def source_balance
    return from_category.holding_calculator.balance if from_category.present?

    CategoryLedger.new(user.categories.expenses.to_a, user: user).available
  end

  def source_name = from_category&.name || "Available"
end
