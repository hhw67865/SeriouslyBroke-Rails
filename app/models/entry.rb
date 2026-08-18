# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true
  accepts_nested_attributes_for :item

  # An entry may name the pool it actually landed in, overriding its category's.
  # An employer splitting a paycheck across two accounts is two deposits, and each
  # one has to be able to name its own destination.
  belongs_to :pool, optional: true

  has_many :pool_movements, foreign_key: :source_entry_id, dependent: :destroy, inverse_of: :source_entry

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :pool_must_belong_to_user
  validate :income_must_land_in_an_account

  delegate :user, to: :item
  delegate :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :tracked, -> { where(categories: { tracked: true }) }

  # EVERY ENTRY WHOSE POOL IS NAMED `name`, ASKED THE WAY EVERY BALANCE ASKS IT.
  #
  # `PoolBalanceLedger::ENTRY_POOL_ID` — `COALESCE(entries.pool_id, categories.pool_id)` — is this
  # app's one SQL answer to "which pool does this entry reach", and it is the entry's OWN pool
  # first. Search used to walk `item → category → pool` instead, which is the second half of that
  # COALESCE with the first half dropped: an entry carrying an override was found under the lane it
  # had overridden AWAY FROM and not under the one holding its money. Seeds and factories write
  # that column (no UI does yet), so the two readers already disagreed about rows in the database.
  #
  # An INNER JOIN, matching the ledger's own: an entry whose category has no pool and which carries
  # no override reaches NO pool — `COALESCE(NULL, NULL)` is NULL — and it is correctly absent from
  # every pool's results rather than swept into one by a LEFT JOIN's nulls.
  #
  # `joins(item: :category)` is required by the expression itself (it reads `categories.pool_id`)
  # and is the same inner join `Entry.expenses` and its siblings carry, so a search composed on top
  # of a type filter joins nothing twice.
  scope :in_pool_named,
        lambda { |name|
          joins(item: :category)
            .joins("INNER JOIN pools ON pools.id = #{PoolBalanceLedger::ENTRY_POOL_ID}")
            .where("pools.name ILIKE ?", "%#{name}%")
        }

  # Define searchable fields using the DSL
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
  # NOT `through: [:item, :category, :pool]`, which is why the DSL grew a `:scope` type — see
  # `.in_pool_named` above and ModelSearchable::SearchMethods#search_by.
  searchable :pool, type: :scope, scope: :in_pool_named, label: "Pool"

  # entry override -> category's pool -> nowhere.
  #
  # The chain ENDS at the category, and the sibling half says why: Task 8 removed
  # `Category#effective_pool`'s `|| user&.default_account` because no ledger implemented it —
  # every balance resolves an entry through `COALESCE(entries.pool_id, categories.pool_id)`
  # (`PoolBalanceLedger::ENTRY_POOL_ID`), and `Σ pools == your bank balance` turned on which of the
  # two answers you asked for. This line and that one are one rule in two halves, so this comment
  # is kept in step with it rather than left describing a third step that no longer exists.
  def effective_pool
    pool || resolved_category&.effective_pool
  end

  private

  # `category` and `user` are delegations through `item`, so on a half-built entry they
  # raise rather than return nil. Everything below reaches the category through here so
  # the guard can never be half-applied to one link and not the other.
  def resolved_category
    item&.category
  end

  # Records, not ids: under `build` an unsaved association leaves `*_id` nil on both
  # sides, and `nil == nil` would wave a foreign pool through.
  def pool_must_belong_to_user
    return if pool.blank? || resolved_category.blank?

    errors.add(:pool, "must belong to the same user") unless pool.user == resolved_category.user
  end

  # The counterpart to Category#income_must_land_in_an_account. The override is a second
  # channel to the same destination, so it carries the same rule: income lands in an
  # account, never directly in an envelope.
  def income_must_land_in_an_account
    return if pool.blank? || !resolved_category&.income?

    errors.add(:pool, "must be an account for income entries") unless pool.pool_type_account?
  end
end
