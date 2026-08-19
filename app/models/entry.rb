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
  #
  # `ENTRY_POOL_JOINS` sits BETWEEN the two, because the bare `pools` join below reads the
  # expression and the expression reads the aliased `category_pools` — a join cannot be defined
  # after the term it resolves. Those two are aliased for this scope's sake specifically: the
  # `INNER JOIN pools` here is the one bare `pools` in the app that composes with the constant, and
  # a second unaliased one would make every `pools.*` reference in this query ambiguous.
  scope :in_pool_named,
        lambda { |name|
          joins(item: :category)
            .joins(*PoolBalanceLedger::ENTRY_POOL_JOINS)
            .joins("INNER JOIN pools ON pools.id = #{PoolBalanceLedger::ENTRY_POOL_ID}")
            .where("pools.name ILIKE ?", "%#{name}%")
        }

  # EVERY ENTRY THAT REACHES ONE POOL — `PoolBalanceLedger::ENTRY_POOL_ID` narrowed to a single id,
  # and THE ONE PLACE THAT NARROWING IS SPELLED.
  #
  # It lives here rather than inside PoolCalculator because it had grown a second reader that was
  # not a reader of it at all: `Pool#spending_rows` built the pool page's timeline out of
  # `has_many :entries, through: :items` — the category's-pool half of the rule with the override
  # arm and (after main-account spec §3) the DATE arm both missing. The pool page therefore listed
  # a pre-start entry under an envelope whose balance, two inches above it, had already sent that
  # money to main; the list and the tiles it explains described different money. Promoting the
  # narrowing to a scope is what makes "one rule, one reader" true of the pool page as well as of
  # the balances — `PoolCalculator#entries_for_pool` is this scope now, not a sibling of it.
  #
  # The joins are the constant's contract (see `ENTRY_POOL_JOINS`); `item: :category` comes first
  # because the expression reads `categories.pool_id`, and it is the same inner join `.expenses`
  # and `.incomes` carry, so a caller composing this with one of those joins nothing twice.
  scope :reaching_pool,
        lambda { |pool|
          joins(item: :category)
            .joins(*PoolBalanceLedger::ENTRY_POOL_JOINS)
            .where("#{PoolBalanceLedger::ENTRY_POOL_ID} = :id", id: pool.id)
        }

  # Define searchable fields using the DSL
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
  # NOT `through: [:item, :category, :pool]`, which is why the DSL grew a `:scope` type — see
  # `.in_pool_named` above and ModelSearchable::SearchMethods#search_by.
  searchable :pool, type: :scope, scope: :in_pool_named, label: "Pool"

  # entry override -> category's pool, from its start date -> the user's main account -> nowhere.
  #
  # THE RUBY HALF OF `PoolBalanceLedger::ENTRY_POOL_ID`, arm for arm, and the pair is where this
  # app's one landing rule is written down in Ruby. The override is this method's own; everything
  # after it belongs to `Category#effective_pool`, which is why THIS is the half that supplies the
  # DATE — an entry knows when it happened and a category does not.
  #
  # `date` IS PASSED RATHER THAN LEFT TO THE DEFAULT, and that is the whole of what the start-date
  # rule (main-account spec §3) changed here. Without it this method answered about TODAY for an
  # entry filed last year: the ledger had the money in the user's main account and this said the
  # envelope, an inch apart on the entry form's impact card. Task 8's note about the two readers of
  # one question stands — it was simply a different question that came apart this time.
  #
  # `|| Date.current` because a keyword default cannot rescue an explicit nil, and a half-built
  # entry (validated for `date` presence, so never a saved one) still has to answer something.
  def effective_pool
    pool || resolved_category&.effective_pool(on: date || Date.current)
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

  # THE SECOND CHANNEL, NOT A SECOND COPY — §7a's "merge the duplicate income validators on
  # `Entry` and `Category`", resolved by reading both (plan 3, task 6). They share a NAME and a
  # sentence and they guard DIFFERENT COLUMNS ON DIFFERENT TABLES:
  #
  #   * `Category#income_must_land_in_an_account` polices `categories.pool_id` — where an income
  #     category's spending lands by default, for every entry it will ever carry.
  #   * this one polices `entries.pool_id`, the per-entry OVERRIDE. `ENTRY_POOL_ID` is
  #     `COALESCE(entries.pool_id, categories.pool_id)`, so the override is the half that WINS:
  #     an income category correctly pointed at Checking could still have a single paycheck
  #     entry re-pointed into an envelope, and the category's validator never sees that write.
  #
  # So neither can delegate to the other — the two are the two halves of the COALESCE, and a rule
  # about a resolved value has to be asserted at every place the value can be set. What is shared
  # is the PREDICATE (`pool.pool_type_account?`), which is one method on `Pool` and already the
  # single home for "is this an account". Collapsing them into one validator on one model would
  # mean one of the two writes going unguarded, which is the defect this branch has found in every
  # task, not the fix for it.
  #
  # The rule itself: income lands in an account, never directly in an envelope — the allocation
  # rules move it out of the account afterwards.
  def income_must_land_in_an_account
    return if pool.blank? || !resolved_category&.income?

    errors.add(:pool, "must be an account for income entries") unless pool.pool_type_account?
  end
end
