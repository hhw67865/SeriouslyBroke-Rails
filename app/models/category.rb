# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  belongs_to :pool, optional: true, touch: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_one :budget, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :category_type, presence: true
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

  enum :category_type,
       {
         expense: 0,
         income: 1,
         savings: 2
       }

  before_validation :destroy_budget_if_not_expense
  before_validation :destroy_budget_if_pool_linked

  validate :budget_only_for_expense
  validate :income_must_land_in_an_account

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :savings, -> { where(category_type: :savings) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :budgetable, -> { expenses.where(pool_id: nil) }
  scope :pool_covered, -> { expenses.where.not(pool_id: nil) }

  scope :with_type,
        lambda { |type|
          case (type || :expense).to_sym
          when :expense then expenses.includes(:budget, :pool, :items)
          when :income then incomes.includes(:items)
          when :savings then savings.includes(:items, :pool)
          end
        }

  # Configure searchable fields
  searchable :name, label: "Name"

  def budgetable?
    expense? && pool_id.nil?
  end

  def pool_covered?
    expense? && pool_id.present?
  end

  # SPENDING THAT COMES OUT OF THE BUFFER — the rate detector's population, and a superset of
  # #budgetable? by exactly one shape: a category pointing at an ACCOUNT.
  #
  # `budgetable?` ("no pool at all") used to be that population, and its sentence — *"this comes out
  # of your buffer, an envelope would hold it"* — is just as literally true of a category pointing
  # at an account, because an account IS the buffer. It became reachable in bulk when Task 8's
  # fix round made a destroyed envelope's categories re-point to the account: every category the
  # user has ever un-enveloped now points at one, and under `budgetable?` the app would have gone
  # permanently silent about spending it had just handed back to the buffer.
  #
  # NOT the same question as #budgetable?, which stays exactly as it was: that one is "may this
  # category carry a category-mode cap", and `Budget#category_must_not_have_pool` answers no for an
  # account-pointed category. A cap on buffer spending is what an envelope replaces, so the two
  # readers diverging here is the point rather than a wrinkle.
  #
  # WHAT THE DIVERGENCE COSTS THE USER, NAMED RATHER THAN LEFT TO BE DISCOVERED. A category whose
  # envelope was deleted now points at an account, so it is `buffer_funded?` but NOT `budgetable?`,
  # and three readers part company on exactly that shape:
  #
  #   * `Budget`'s category-mode cap — the form's collection is `expenses.budgetable`
  #     (`budgets/_form`, `BudgetsController#set_category`), so the category can no longer be given
  #     a monthly cap.
  #   * `Entry.budgetable_expenses` (`expenses.where(categories: { pool_id: nil })`), and
  #   * `DashboardPresenter#tracked_budgetable_expense_categories`
  #     (`tracked_expense_categories.select(&:budgetable?)`), which together feed the Dashboard's
  #     budget-health figures — `total_tracked_budgetable_expenses` and the Expenses/All tab
  #     breakdowns. The spending moves out of the "budgeted" band and into `pool_covered`.
  #
  # Both are RECOVERABLE and neither destroys anything: clearing the category's pool puts it back in
  # every one of those sets, and accepting the rate suggestion this predicate now produces gives it
  # a real envelope, which is the better answer and the one the panel offers. Recorded here so the
  # whole-plan review sees the family rather than meeting one member of it on a screen.
  def buffer_funded?
    expense? && (pool.nil? || pool.pool_type_account?)
  end

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  # WHICH POOL THIS CATEGORY'S SPENDING REACHES, and it is now the same rule the ledger runs on.
  #
  # It used to read `pool || user&.default_account`, and that fallback was a promise nothing kept.
  # `PoolCalculator` and `PoolBalanceLedger` both resolve an entry through
  # `COALESCE(entries.pool_id, categories.pool_id)` (PoolBalanceLedger::ENTRY_POOL_ID) — no default
  # account anywhere — so a pool-less category's spending reached the default account HERE and
  # reached nothing THERE. Two readers of one question, which is the defect this branch has found
  # in every task, and Task 8 made it matter: destroying a pool used to nullify its categories, and
  # the difference between the two answers was the difference between `Σ pools` being conserved and
  # rising by the pool's lifetime spending.
  #
  # The SQL wins, because the SQL is what every balance, every envelope status and the invariant
  # itself are computed from. This reader is corrected to agree with it rather than the ledger being
  # widened to agree with this one — widening would put a user's whole unpooled expense history into
  # their nominated account's buffer, silently changing every balance on Home.
  #
  # Kept as a named reader rather than folded into `pool`: `Entry#effective_pool` is the other half
  # of the same chain (the entry's own override first, this second), and the pair is where the rule
  # is written down in Ruby — so that method's comment has to move with this one, and did.
  #
  # Grepped before changing it. `Entry#effective_pool` calls this and is the ONLY caller of it
  # anywhere in `app/`; nothing in `app/`, `lib/`, `db/` or the views calls THAT one, so no rendered
  # figure and no write depended on the fallback and correcting it could not move a screen. The
  # header this replaces claimed "PoolCalculator calls it", which had been untrue since Plan 2b
  # moved the calculator onto ENTRY_POOL_ID.
  def effective_pool
    pool
  end

  private

  def destroy_budget_if_not_expense
    return unless category_type_changed? && !expense? && budget

    budget.destroy
    self.budget = nil
  end

  def destroy_budget_if_pool_linked
    return unless pool_id_changed? && pool_id.present? && budget

    budget.destroy
    self.budget = nil
  end

  def budget_only_for_expense
    errors.add(:budget, "can only be set for expense categories") if budget.present? && !expense?
  end

  # Income lands in an account, never directly in an envelope: the allocation rules
  # move it out of the account afterwards.
  def income_must_land_in_an_account
    return if pool.blank? || !income?

    errors.add(:pool, "must be an account for income categories") unless pool.pool_type_account?
  end
end
