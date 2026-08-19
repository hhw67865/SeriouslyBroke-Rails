# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true

  # EVERY CATEGORY NAMES ITS LANE (plan 3 decision 3). `optional: true` is gone, and the required
  # `belongs_to` IS the presence validation — one spelling, the Rails one, rather than a
  # `validates :pool, presence: true` sitting beside an association that says the opposite.
  #
  # The nil `pool_id` used to mean "the user's default account", and it was a promise nothing kept:
  # `PoolBalanceLedger::ENTRY_POOL_ID` resolves `COALESCE(entries.pool_id, categories.pool_id)` to
  # NOTHING for such a category, so its spending reached no pool at all while `Σ pools == bank
  # truth` claimed otherwise. The cutover migration points every nil at the user's default account
  # and verifies it in raw SQL; this is the line that stops one coming back.
  belongs_to :pool, touch: true

  has_many :items, dependent: :destroy
  has_many :entries, through: :items

  # `has_one :budget` IS GONE (plan 3, task 4). Task 3 kept it alive for one commit because
  # `CategoryCalculator#monthly_budget_rate` still read `category.budget&.amount` and the
  # dashboard's budget chart stood on it; both are deleted with decision 6, so the association is
  # callerless as well as answerless. A Budget belongs to a POOL — `budgets.category_id` is a
  # column with no Ruby left, and Task 6 drops it.

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :category_type, presence: true
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

  # TWO TYPES, NOT THREE (plan 3 decision 5). `savings: 2` is gone: money moving into a goal is a
  # `PoolMovement`, not an entry in a savings CATEGORY, and the cutover migration converted every
  # savings entry this app ever wrote. A category now says one of two things — money left your life
  # (expense) or money entered it (income) — and where it LANDS is `pool_id`'s answer, which is
  # where a goal lives.
  #
  # INTEGER 2 IS RETIRED AND NEVER REUSED. `categories.category_type` still holds the column and
  # nothing writes a 2 any more; a third type added later takes 3. Reusing 2 would silently
  # re-type any row that survived in a backup, an export or a staging database that missed the
  # migration.
  #
  # THE ONE PLACE 2 IS STILL WRITTEN DOWN is `CutoverToEnvelopeBudgeting::SAVINGS_CATEGORY`, which
  # is the value the migration goes looking for — a fact about the rows it meets, not a type this
  # app has. Plan 3 task 6 checked the column for a change and there is none to make: a `CHECK
  # (category_type IN (0,1))` would refuse the very rows the cutover exists to convert, and it
  # would have to be added and dropped around every run of `spec/migrations/cutover_spec.rb`.
  enum :category_type,
       {
         expense: 0,
         income: 1
       }

  validate :pool_must_belong_to_user
  validate :pool_must_be_reachable
  validate :income_must_land_in_an_account

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }

  # `:budget` LEFT THE EXPENSE PRELOAD with the cap card it fed: the Categories index used to print
  # `category.budget&.amount` and now prints the pool the spending comes out of, so preloading the
  # association would be one query for a link that is nil on every row.
  #
  # EXPENSE IS THE `else`, NOT A THIRD `when`. This was a three-armed case returning NIL for
  # anything it did not recognise, and `?type=savings` is now exactly that — a bookmark, a browser
  # history entry or a link in an old email — which reached `apply_search(nil, …)` and 500ed.
  # CategoriesController sanitises `@type` for the same reason (the heading and the tab strip must
  # not say "Savings" over a list of expenses); this arm is the model-side half, so a caller that
  # forgets still gets a relation.
  scope :with_type,
        lambda { |type|
          case (type || :expense).to_sym
          when :income then incomes.includes(:items)
          else expenses.includes(:pool, :items)
          end
        }

  # Configure searchable fields
  searchable :name, label: "Name"

  # SPENDING THAT COMES OUT OF THE BUFFER — the rate detector's population, the Categories page's
  # account-pointed arm, and the one predicate all of them read.
  #
  # THE NIL ARM DIED WITH THE SHAPE (plan 3 decision 3). This used to be
  # `pool.nil? || pool.pool_type_account?`, because a category with no pool at all was the ordinary
  # pre-cutover way to spend from the buffer. `belongs_to :pool` is required now, so the first half
  # can no longer be true of a saved record and the second half is the whole question: an account
  # IS the buffer (§7.1), so an expense category pointing at one is spending that nothing reserves.
  #
  # The sentence three screens say about this set is unchanged and stays literally true — *"No
  # envelope — this spending isn't budgeted. It comes out of your buffer"* on the Categories page,
  # the entry form's impact card and `budget_page/_suggestion_rate`. Only the spelling narrowed.
  #
  # The family of readers this predicate used to diverge from — `budgetable?`, `Category.budgetable`
  # and `Entry.budgetable_expenses`, all of which meant "no pool at all" — is gone: with no pool-less
  # category expressible there is nothing left for them to be a different answer TO.
  def buffer_funded?
    expense? && pool.pool_type_account?
  end

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  # WHICH POOL THIS CATEGORY'S SPENDING REACHES *ON A GIVEN DAY*, and it is the same rule the
  # ledger runs on — THE START-DATE RULE INCLUDED (main-account spec §3).
  #
  # `on:` IS THE WHOLE OF WHAT §3 ADDED, and the reason this reader could not stay date-free. An
  # envelope only counts its categories' spending from its `start_date` onward; earlier spending
  # reads against the user's MAIN account. So "which pool does this category's spending reach" has
  # no answer without a day attached — the same category answers `Groceries` for June and
  # `Checking` for May. It defaults to `Date.current` because the question asked without a date is
  # the question asked about spending happening now, which is what every caller that omits it means.
  #
  # THE DAY IS THE USER'S DAY, taken through `#local_day`, because ENTRY_POOL_ID renders
  # `entries.date` in the owner's zone before comparing. One rule in two languages only holds if
  # both languages agree about when midnight was.
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
  # WHO CALLS IT NOW, AND THE GREP CLAIM THAT USED TO STAND HERE IS WITHDRAWN. This header said
  # "`Entry#effective_pool` calls this and is the ONLY caller of it anywhere in `app/`; nothing in
  # `app/`, `lib/`, `db/` or the views calls THAT one" — true when the fallback was removed, and
  # BOTH HALVES FALSE since Task 4:
  #
  #   * `EntryImpactPresenter#pool` calls THIS one, on every render of the entry form, and
  #   * `EntryImpactPresenter#own_contribution` calls `Entry#effective_pool` — to decide whether
  #     the entry being edited is already counted in the pool the card is describing, which is the
  #     difference between the card printing "$240 → $185 left" and printing it twice-spent.
  #
  # So a rendered balance now depends on this reader's CURRENT behaviour. What the withdrawn
  # sentence was really recording is a fact about a moment: the fallback was removed at a time when
  # nothing depended on it, so correcting it could not move a screen. Readers have since arrived,
  # and they are readers of what it does today — changing it now moves figures on the entry form.
  # (The claim before that one — "PoolCalculator calls it" — had been untrue since Plan 2b moved
  # the calculator onto ENTRY_POOL_ID. A grep pasted into a comment is a fact with an expiry date;
  # what stays true is WHY this agrees with the SQL, which is the paragraph above.)
  #
  # THE THREE ARMS ARE ENTRY_POOL_ID'S OWN, minus the entry override that belongs to
  # `Entry#effective_pool`: a pool-less category reaches NOTHING (nil, never the main account — the
  # fallback is reserved for history displaced by a start date), an ACCOUNT has no date gate, and
  # an envelope or goal answers for itself only from its start date on.
  def effective_pool(on: Date.current)
    return pool if pool.nil? || pool.pool_type_account?

    local_day(on) >= pool.start_date ? pool : user&.default_account
  end

  private

  # THE CALENDAR DAY AN INSTANT FELL ON, IN THE OWNER'S ZONE — the Ruby half of ENTRY_POOL_ID's
  # `AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(category_users.timezone, 'UTC')`. `entries.date` is a
  # datetime, so a Tokyo user's Aug 1 is stored as Jul 31 15:00 UTC and `.to_date` under an ambient
  # UTC zone (a job, a console, a spec outside a request) would answer Jul 31 while the SQL answers
  # Aug 1. Re-zoning from the USER rather than from `Time.zone` is what makes the two agree wherever
  # this runs, not only inside the request ApplicationController has already wrapped.
  #
  # A DATE PASSES THROUGH UNTOUCHED, and the `DateTime` exclusion is load-bearing: `DateTime < Date`
  # in Ruby, so a plain `is_a?(Date)` test would let a real instant skip the conversion. A Date has
  # no instant to re-zone — `Date#in_time_zone` would invent midnight and shift the day.
  def local_day(moment)
    return moment if moment.is_a?(Date) && !moment.is_a?(DateTime)

    moment.in_time_zone(user&.timezone.presence || "UTC").to_date
  end

  # A CATEGORY'S LANE IS ONE OF ITS OWN USER'S POOLS — the third instance of a rule its two siblings
  # already carry (`Entry#pool_must_belong_to_user`, `Pool#account_is_this_users_account`), and it
  # is written the same way for the same reasons.
  #
  # WHY IT IS HERE WHEN THE CONTROLLERS ALREADY GUARD IT. Both writers of this column scope their
  # lookup to `current_user` — `CategoriesController` builds through `current_user.categories` and
  # picks the pool out of `current_user.pools`, and `PoolsController` never sets it — so no request
  # can reach this validator today. That is a fact about two controllers, not about the column: a
  # console, a rake task, an import, a future API or a `pool_id` that arrives through a nested form
  # writes it with nothing in the way, and a category pointing at a stranger's pool is a leak the
  # app cannot render honestly. Its entries would reach a pool the owner does not own, which makes
  # BOTH users' `Σ pools` disagree with their bank truth — the cutover migration's #preflight!
  # refuses exactly this shape by name for exactly that reason. The controllers are the first layer;
  # this is the durable one.
  #
  # RECORDS, NOT IDS, and both precedents say so in their own comments: under `build` an unsaved
  # association leaves `user_id` nil on both sides, and `nil == nil` would wave a foreign pool
  # through. `pool.user == user` compares two records, so an unsaved pair is compared on identity
  # rather than on two nils that happen to match.
  #
  # SILENT ON NILS, because a missing pool or a missing user is another validator's sentence to say:
  # `belongs_to :pool` and `belongs_to :user` are both required, and adding "must belong to the same
  # user" to a record that names no user at all is a second error about a first error.
  def pool_must_belong_to_user
    return if pool.blank? || user.blank?

    errors.add(:pool, "must belong to the same user") unless pool.user == user
  end

  # MAIN-ACCOUNT SPEC §6: non-main accounts hold money via movements only — no categories, so
  # no entries can ever land in them and their balance mirrors the real bank statement. And a
  # category on an envelope needs the user to HAVE a main account, because the start-date
  # rule's ELSE arm sends the envelope's pre-start history to users.default_account_id — a
  # NULL there silently drops those entries from Σ.
  def pool_must_be_reachable
    return if pool.blank? || user.blank?

    if pool.pool_type_account?
      return if pool == user.default_account
      errors.add(:pool, "must be your main account or an envelope inside one")
    elsif user.default_account.blank?
      errors.add(:pool, "needs a main account first — history before the envelope starts has nowhere to go")
    end
  end

  # Income lands in an account, never directly in an envelope: the allocation rules
  # move it out of the account afterwards.
  #
  # ITS TWIN ON `Entry` STAYS, AND IS NOT A DUPLICATE (§7a's "merge the duplicate income
  # validators", resolved in plan 3, task 6). This one guards `categories.pool_id`; that one
  # guards `entries.pool_id`, the per-entry override that WINS the `COALESCE` this one's value
  # loses. `Entry#income_must_land_in_an_account` carries the full reasoning.
  def income_must_land_in_an_account
    return if pool.blank? || !income?

    errors.add(:pool, "must be an account for income categories") unless pool.pool_type_account?
  end
end
