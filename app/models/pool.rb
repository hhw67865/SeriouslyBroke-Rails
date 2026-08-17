# frozen_string_literal: true

class Pool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :categories, dependent: :nullify
  has_many :budgets, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items

  # Entries that named this pool directly, overriding their category's. Nullified on
  # destroy for the same reason categories are: the entry falls back down the chain
  # rather than blocking the delete on a foreign key.
  has_many :override_entries, class_name: "Entry", dependent: :nullify, inverse_of: :pool

  belongs_to :account, class_name: "Pool", optional: true
  has_many :child_pools,
           class_name: "Pool",
           foreign_key: :account_id,
           dependent: :restrict_with_error,
           inverse_of: :account

  has_many :movements_in,
           class_name: "PoolMovement",
           foreign_key: :to_pool_id,
           dependent: :destroy,
           inverse_of: :to_pool
  has_many :movements_out,
           class_name: "PoolMovement",
           foreign_key: :from_pool_id,
           dependent: :destroy,
           inverse_of: :from_pool

  # Prefixed so `pool_type_account?` ("is an account") can never be misread as the
  # `account` association ("the account this pool sits inside").
  enum :pool_type, { account: 0, budget: 1, savings: 2 }, prefix: true

  # Named `*_pools` so they can never be misread as the `budgets` association
  # (`pool.budgets` holds Budget records; `Pool.budget_pools` holds Pool records).
  scope :accounts, -> { where(pool_type: :account) }
  scope :budget_pools, -> { where(pool_type: :budget) }
  scope :savings_pools, -> { where(pool_type: :savings) }
  scope :by_priority, -> { order(:priority, :name) }

  # THE POOLS AN ACCOUNT ACTUALLY FILLS, and therefore the ones a fill order is over: an envelope
  # with no funding rule asks for nothing, AllocationCalculator#fill drops its zero-ask row before
  # the waterfall reaches it, and the Budget page — which groups rules under the pool they fill —
  # has no card to drag for it. One reader for that set, because `.apply_fill_order` refuses a
  # list that is not exactly it and BudgetPagePresenter renders exactly it.
  scope :in_fill_order, -> { joins(:budgets).distinct }

  attr_accessor :create_expense_category, :create_savings_category

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :target_amount, presence: true, if: :pool_type_savings?
  validates :start_date, presence: true
  # `pools.priority` is NOT NULL with no model-side guard, and the form renders it as an
  # integer input: a cleared box submits "", which casts to nil and reached the database as a
  # NotNullViolation 500. The non-negative bound is the obligation deferred when the column
  # landed — a negative priority outranks every pool the user meant to fund first.
  validates :priority, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  validate :account_matches_pool_type
  validate :pool_type_stays_account_while_it_holds_pools

  after_initialize :set_default_start_date, if: :new_record?
  after_create :create_auto_categories

  # Configure searchable fields
  searchable :name, label: "Name"
  searchable :category, through: :categories, column: :name, label: "Category"

  # THE FILL ORDER, WRITTEN — the only writer for `priority` outside the pool form, and the one
  # the Budget page's drag and its ▲▼ buttons both go through. `pool_ids` is ONE account's
  # rule-carrying envelopes in the order the user just put them in. Answers the account on
  # success and NIL on refusal, which is the whole vocabulary the caller needs: nothing partial
  # exists.
  #
  # DENSE, not "shift the moved row and leave the rest": `by_priority` is `[priority, name]`, so
  # a sparse rewrite leaves ties whose winner is decided by a name — the defect Plan 1 shipped in
  # its waterfall. The rewrite is dense over the account's WHOLE set of pools, not merely over
  # the submitted ones, and each unsubmitted pool KEEPS ITS PLACE in the sequence: a pool with no
  # rule would otherwise be left on an old number that collides with a renumbered one, and the
  # tie-break the density exists to defeat would decide which of the two Home draws first.
  # Its number moves, its rank does not.
  #
  # EVERY REFUSAL IS THE SAME REFUSAL and writes nothing at all:
  #   * an id that is not this user's (`user.pools` is the only lookup — an id belonging to
  #     someone else simply is not found, so `pools.size` falls short),
  #   * ids from two accounts, or from none (a pool with no account is funded by no
  #     distribution, so it has no fill order to be in),
  #   * a duplicate id (which would make the list shorter than it looks and silently drop a pool),
  #   * a list that is not the account's whole `in_fill_order` set — a page whose rules have
  #     changed under it, submitting an order for pools that are no longer the ones being
  #     ordered. Nothing is written and the page comes back saying so, rather than a partial
  #     write leaving an order nobody chose.
  def self.apply_fill_order(user:, pool_ids:)
    ids = Array(pool_ids).map(&:to_s)
    pools = fill_order_pools(user, ids)
    return if pools.nil?

    account = fill_order_account(user, pools.values)
    return if account.nil? || account.child_pools.in_fill_order.ids.map(&:to_s).sort != ids.sort

    transaction { write_fill_order(account, ids, pools) }
    account
  end

  # The submitted pools dropped into the slots the submitted pools already hold, everything else
  # left where it stands, and the whole account renumbered 0,1,2… off the result.
  def self.write_fill_order(account, ids, pools)
    queue = ids.dup
    account.child_pools.by_priority
      .map { |pool| pools.key?(pool.id.to_s) ? pools.fetch(queue.shift) : pool }
      .each_with_index { |pool, index| pool.update!(priority: index) }
  end
  private_class_method :write_fill_order

  # The submitted pools keyed by their id as it arrived on the wire, or NIL if the list itself is
  # not a list of this user's pools: empty, holding a duplicate (which would make it shorter than
  # it looks and drop a pool), or naming an id `user.pools` does not find — someone else's, or
  # nothing at all, and the two deserve the same answer.
  def self.fill_order_pools(user, ids)
    return if ids.empty? || ids.uniq.size != ids.size

    pools = user.pools.where(id: ids).index_by { |pool| pool.id.to_s }
    pools if pools.size == ids.size
  end
  private_class_method :fill_order_pools

  # The one account every submitted pool sits inside, or nil if that is not one account. Looked
  # up through `user.pools.accounts` rather than through `pools.first.account`, so an envelope
  # whose `account_id` points at a pool that is not an account — or not this user's — is a
  # refusal rather than a silent write against whatever that row happens to be.
  def self.fill_order_account(user, pools)
    account_ids = pools.map(&:account_id).uniq
    return unless account_ids.one? && account_ids.first.present?

    user.pools.accounts.find_by(id: account_ids.first)
  end
  private_class_method :fill_order_account

  # Entries scoped to start_date and filtered by category type.
  #
  # The `start_date..` filter is a deliberate divergence from PoolCalculator#balance, which
  # dropped it: these three feed the savings-goal *timeline*, which is a story about a goal
  # and rightly begins when the goal did, while the balance is all the money in the pool
  # regardless of when it arrived. PoolsController#show therefore renders a timeline and a
  # balance computed on different rules, on purpose — a pre-start entry counts toward the
  # balance without appearing in the list above it.
  # TODO(plan-3): revisit once savings-category entries become movements; the timeline will
  # need a movement-aware source and this is the moment to decide if the cutoff survives.
  def contribution_entries
    entries.joins(item: :category).where(categories: { category_type: :savings }).where(date: start_date..)
  end

  def withdrawal_entries
    entries.joins(item: :category).where(categories: { category_type: :expense }).where(date: start_date..)
  end

  def timeline_entries
    contribution_entries.or(withdrawal_entries)
  end

  # `terms:` threads straight through to the calculator underneath and DEFAULTS TO NOTHING, which
  # is what keeps this method the unbatched single-pool door it has always been: a model
  # validation, a controller confirmation sentence and `#total` below all ask about one pool, and
  # one pool is five queries whether they are grouped or not. Only the callers that ITERATE pools
  # build a PoolBalanceLedger and pass its terms down here — see HomePresenter#calculator_for.
  #
  # A keyword here rather than those callers reaching for `PoolCalculator.new` themselves, so
  # this stays the one place a calculator is built from a pool. A second construction path is how
  # a keyword ends up honoured on one screen and forgotten on the next.
  def calculator(as_of: nil, today: Date.current, net_of_sweep: false, pending: PoolCalculator::Pending.none,
                 terms: nil)
    PoolCalculator.new(
      self, as_of: as_of, today: today, net_of_sweep: net_of_sweep, pending: pending, terms: terms
    )
  end

  # `pending:` threads straight through to the calculator underneath, exactly as it does here:
  # a status is a reading of a balance, so a status of a pool that has not yet received this
  # distribution's money is a status of the wrong balance. It is what lets the distribution
  # screen ask "does this envelope still make it if I fund $200 instead of $500" in the app's
  # own vocabulary rather than inventing a second one.
  # `terms:` threads down the same way and for the same reason, and defaults to nothing here too:
  # a view or a controller asking one pool how it is doing pays five queries either way.
  def status(today: Date.current, pending: PoolCalculator::Pending.none, terms: nil)
    PoolStatus.new(self, today: today, pending: pending, terms: terms)
  end

  # What the bank actually says: unallocated cash plus every pool inside it.
  def total
    calculator.current_balance + child_pools.sum { |pool| pool.calculator.current_balance }
  end

  private

  def account_matches_pool_type
    return errors.add(:account, "cannot be set on an account") if pool_type_account? && account_id.present?
    return if pool_type_account?

    return require_account_for_budget_pools if account.blank?

    errors.add(:account, "must be an account") unless account.pool_type_account?
    # Records, not ids: with neither the pool nor its parent saved both `user_id`s are nil,
    # and `nil == nil` waves another user's account through.
    errors.add(:account, "must belong to the same user") unless account.user == user
  end

  # `account_matches_pool_type` only ever looks upward, at the parent, and
  # `dependent: :restrict_with_error` guards destroy alone — so nothing stopped an account
  # that holds envelopes from being turned into an envelope itself. Once it was,
  # HomePresenter dropped it from `accounts`, its children belonged to no group `pools_for`
  # could find, and `orphan_pools` skipped them because their `account_id` was not nil: the
  # envelopes rendered nowhere on Home while still counting toward what the period must
  # cover. Only the *change* is refused; an account that keeps its type saves as before.
  def pool_type_stays_account_while_it_holds_pools
    return if pool_type_account?
    return unless persisted? && pool_type_was == "account"
    return unless child_pools.exists?

    errors.add(:pool_type, "can't be changed while other pools sit inside this account — move them out first")
  end

  # Savings pools may stay account-less until Plan 3's data migration backfills them;
  # budget pools are new in this plan and must name an account from day one.
  # TODO(plan-3): tighten to include savings pools once the account backfill lands
  def require_account_for_budget_pools
    errors.add(:account, "must be set for budget pools") if pool_type_budget?
  end

  def set_default_start_date
    self.start_date ||= Date.current
  end

  def create_auto_categories
    create_linked_category(:expense) if boolean_cast(create_expense_category)
    create_linked_category(:savings) if boolean_cast(create_savings_category)
  end

  def create_linked_category(type)
    base_name = "#{name} #{type.to_s.capitalize}"
    categories.create!(
      user: user,
      name: unique_category_name(base_name),
      category_type: type
    )
  end

  def unique_category_name(base_name)
    candidate = base_name
    suffix = 2
    while user.categories.exists?(["LOWER(name) = ?", candidate.downcase])
      candidate = "#{base_name} #{suffix}"
      suffix += 1
    end
    candidate
  end

  def boolean_cast(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
