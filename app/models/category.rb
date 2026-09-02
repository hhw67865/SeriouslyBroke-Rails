# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  # ONBOARDING STEP 3'S LATCH (main-account spec §5): the name of the auto-created category that
  # records the one-time main correction, and the ONE spelling of it — `OpeningBalancesController`
  # and `HomePresenter` both read #opening_balance below rather than each carrying their own copy
  # of this string, so a typo in one cannot leave the controller's latch and the card's render gate
  # disagreeing about which category means "already done".
  #
  # THE LATCH IS DELIBERATELY REOPENABLE (fix round 1 — MED-2/LOW-2/MED-3 doc ruling). Renaming
  # or deleting the row this scope matches reopens onboarding's card on the next Home load —
  # there is no separate "onboarding complete" flag guarding against it. That is ACCEPTED, not a
  # gap: it is the only escape hatch a user has for a mistyped opening figure, since
  # `OpeningBalancesController` offers no `destroy` of its own. A user who wants to correct the
  # correction renames or deletes the category through the ordinary categories screen and the
  # card comes back, honestly, exactly as if onboarding had never finished.
  OPENING_BALANCE_NAME = "Opening Balance"

  belongs_to :user, touch: true

  # A DYING LANE, OPTIONAL AGAIN FOR THE LENGTH OF THIS BRANCH (two-ledger spec §5, Task 2).
  #
  # Plan 3 made this required, and the reason was real: a nil `pool_id` used to mean "the user's
  # default account" and nothing kept the promise — `PoolBalanceLedger::ENTRY_POOL_ID` resolves
  # `COALESCE(entries.pool_id, categories.pool_id)` to NOTHING for such a category, so its spending
  # reached no pool at all while `Σ pools == bank truth` claimed otherwise.
  #
  # That hazard belongs to a model where the POOL holds the money. Under the two-ledger model the
  # category holds it (§2), spending that reaches no pool is spending that drains AVAILABLE, and
  # the only pool a category will ever name again is an account — an association Task 8 deletes
  # outright. Two shapes already exist that the required version refuses: the savings categories
  # Task 1's migration minted, and the categories Task 7's screens create with no account question
  # asked at all. Nothing about the meaning of a PRESENT `pool_id` changes — `#pool_must_be_
  # reachable` and `#income_must_land_in_an_account` still govern it, and both were already silent
  # on a blank pool.
  belongs_to :pool, optional: true, touch: true

  has_many :items, dependent: :destroy
  has_many :entries, through: :items

  # THE RULES THIS CATEGORY IS FUNDED BY (two-ledger spec §3): `budgets.category_id` replaces
  # `budgets.pool_id`, one category to one budget line. `dependent: :destroy` because a rule with
  # no category to fund is a demand on the waterfall for money nothing can hold.
  has_many :budgets, dependent: :destroy

  # BOTH SIDES OF THE PURPOSE LEDGER, and both are `dependent: :destroy` because `allocations` has
  # real foreign keys to `categories` with no ON DELETE: without these, destroying a category that
  # ever held money raises rather than deletes, and `user.destroy` with it.
  #
  # DESTROYING A CATEGORY GIVES ITS MONEY BACK TO AVAILABLE, which is the honest outcome and not a
  # loss: every allocation deleted here was a claim on money the pot still holds, so `pot + Σ
  # accounts == available + Σ holdings` is true again the instant the rows are gone.
  has_many :allocations_in,
           class_name: "Allocation",
           foreign_key: :to_category_id,
           dependent: :destroy,
           inverse_of: :to_category
  has_many :allocations_out,
           class_name: "Allocation",
           foreign_key: :from_category_id,
           dependent: :destroy,
           inverse_of: :from_category

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

  # THE THREE PURPOSE-LEDGER COLUMNS, VALIDATED TOGETHER AND BEHIND ONE GUARD — see
  # #holding_columns_are_sane for both halves of why.
  validate :holding_columns_are_sane
  validate :pool_must_belong_to_user
  validate :pool_must_be_reachable
  validate :income_must_land_in_an_account

  # A CATEGORY THAT STOPS BEING INCOME TAKES ITS ENTRIES' MIRROR MOVEMENTS WITH IT (main-account
  # spec §4, final whole-branch review — I-3).
  #
  # An income entry always LANDS in main; a user who says it ended up in Ally gets one mirroring
  # `transfer` movement main → Ally (`Entry#route_income_to!`). `EntriesController#sync_income_
  # routing` is the only other caller of that method, and it syncs entry-side only — so flipping
  # the CATEGORY from income to expense through the ordinary edit form (`category_type` is
  # permitted) left every one of its entries' movements standing with nothing behind them: main
  # still debited for money the app no longer thinks arrived, the destination still holding a
  # phantom, and Σ pools split across two accounts on the strength of a routing question an
  # expense is never even asked. The controller already knows the rule for one entry — "not
  # income, so route nowhere" — and this is that same rule asked at the place a whole category's
  # answer can change.
  #
  # `route_income_to!(nil)` RATHER THAN A DELETE OF MY OWN, for the reason its own comment gives:
  # allocation and sweep movements also carry a `source_entry`, and only `kind_transfer` tells a
  # routing mirror apart from a distribution's envelope split. A hand-rolled
  # `where(source_entry: entries)` here would wipe the period's allocation every time somebody
  # re-typed a category.
  #
  # INSIDE THE UPDATE'S OWN TRANSACTION (`after_update`, not `after_update_commit`), so a destroy
  # that will not run takes the type flip down with it rather than leaving the two disagreeing.
  # The guard is the exact pair, income → expense: an expense → income flip has no movements to
  # clear (they are written by the entry path afterwards) and a rename or a colour change is not a
  # type change at all, so neither reaches the query.
  after_update :unroute_entries_that_are_no_longer_income

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }

  # THE LATCH ITSELF, CASE-INSENSITIVE — matching, not merely resembling, the `uniqueness:
  # { case_sensitive: false }` validation above. An exact-case `where(name: OPENING_BALANCE_NAME)`
  # would miss a category a user already named "opening balance" through the ordinary categories
  # screen: the latch would read "not yet recorded" while `create!` below collided with it on the
  # very uniqueness rule this scope has to agree with, turning an onboarding click into a crash.
  # Same spelling `Item#move_to_category` already uses for the same reason.
  scope :opening_balance, -> { where("LOWER(name) = ?", OPENING_BALANCE_NAME.downcase) }

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
  # account-pointed arm, and the one predicate all of them read
  # (`SuggestionEngine#buffer_funded_categories`, `CategoryBudgetPresenter#proposable?`,
  # `DashboardPresenter`'s two halves at :165 and :169, and the three views that say the sentence).
  #
  # THE NIL POOL IS EXPRESSIBLE AGAIN, AND IT ANSWERS FALSE. Three eras, and this comment has to
  # name all of them because the answer to a nil has now been each of the three in turn:
  #
  #   * BEFORE THE CUTOVER, `pool.nil? || pool.pool_type_account?` — a pool-less category was the
  #     ordinary way to spend straight out of the buffer, so nil meant TRUE.
  #   * PLAN 3 made `belongs_to :pool` required, the nil became inexpressible, and the first half
  #     was deleted as unreachable.
  #   * THE TWO-LEDGER TRANSITION (spec §5, Task 2) makes the association optional again — and the
  #     nil means the OPPOSITE of what it meant in the first era. A category with no pool is now a
  #     category that holds its own money (§2), and money a category holds is precisely what this
  #     predicate exists to say is NOT coming out of the buffer. So nil answers FALSE, and the guard
  #     is a deliberate answer rather than nil-safety around a shape nobody can build.
  #
  # The sentence three screens say about this set stays literally true — *"No envelope — this
  # spending isn't budgeted. It comes out of your buffer"* on the Categories page, the entry form's
  # impact card and `budget_page/_suggestion_rate`: a holder is not in this set and never sees it.
  #
  # Pinned in `spec/models/category_holdings_spec.rb`, both directions, on a pool-less category
  # planted VALIDLY — which is itself the fact this era turns on.
  def buffer_funded?
    return false if pool.blank?

    expense? && pool.pool_type_account?
  end

  # DOES THIS CATEGORY HOLD MONEY? (two-ledger spec §3.) Two facts and no third: only an EXPENSE
  # category can hold — income lands in available and is allocated out of it — and it holds from
  # `funded_since` onward, the date it first got a rule or an allocation. A category with no
  # `funded_since` has never been given money to hold, so its spending drains available.
  #
  # This is the predicate every screen asks where it used to ask `pool.pool_type_budget?`.
  def holder? = expense? && funded_since.present?

  # A GOAL IS A HOLDER WITH A TARGET AND NO RULE (spec §3: "a savings category is just a category
  # with a target and typically no refill rule"). The rule half is what tells a goal apart from an
  # envelope somebody also set a ceiling on: a category the waterfall refills every period is being
  # SPENT toward a rate, not SAVED toward a figure.
  #
  # THE CALCULATOR DOES NOT ASK THIS, and an earlier draft of this comment said it did. §3's own
  # "typically" is why: a goal MAY carry a refill rule (the demo's Retirement Supplement does), and
  # such a category is not `savings?` — so `HoldingCalculator` asking this would call it an envelope
  # and sweep the user's savings back to available at the end of every rate period. The funding
  # question is asked of the TARGET instead, in `HoldingCalculator#dateless_goal?`, whose comment
  # carries the whole argument and the measurement. This predicate is the DISPLAY question — is this
  # row a goal to render as one — and the two are deliberately different conditions.
  #
  # It is also exactly the shape Task 1's migration mints out of a savings pool — target, priority,
  # `funded_since`, `tracked: false`, and no rule was ever attached to a goal.
  def savings? = holder? && target_amount.present? && budgets.none?

  # THE RUBY MIRROR OF `CategoryLedger::ENTRY_CATEGORY_ID`, and the ONLY one (Task 2's global
  # constraint): every other reader in this app asks the SQL. Spending counts against this category
  # from `funded_since` onward, compared in the OWNER's calendar day — `#local_day` is the same
  # re-zoning the SQL does with its two `AT TIME ZONE`s, so a Tokyo user's Aug 1 entry, stored
  # `2026-07-31 15:00` UTC, counts on Aug 1 wherever this runs.
  def counts_spending_on?(date)
    holder? && local_day(date) >= funded_since
  end

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  # THE ONE DOOR ONTO WHAT THIS CATEGORY HOLDS (two-ledger spec §2), and the port of
  # `Pool#calculator`: `terms:` threads straight through to the calculator underneath and DEFAULTS
  # TO NOTHING, which keeps this the unbatched single-category door — one category is a handful of
  # queries whether they are grouped or not. Only the callers that ITERATE categories build a
  # `CategoryLedger` and pass its terms down here.
  #
  # A keyword here rather than those callers reaching for `HoldingCalculator.new` themselves, so
  # this stays the one place a calculator is built from a category. A second construction path is
  # how a keyword ends up honoured on one screen and forgotten on the next.
  #
  # `net_of_sweep:` and `pending:` are PROJECTIONS — questions about a ledger nobody has written —
  # and they belong to `HoldingProjection`, which wraps a plain calculator and owns the arithmetic,
  # the twin and the refusal. `HoldingProjection.for` hands back a plain HoldingCalculator when
  # neither is asked for, so the callers that ask none are on exactly the object they expect.
  #
  # IT IS NOT CALLED `#calculator`, AND THAT IS THE COLLISION RATHER THAN A PREFERENCE. That name
  # is `CategoryCalculator`'s — what a category SPENT in a period, which the categories and
  # dashboard screens still ask on every render — and the two answer different questions about the
  # same record. Renaming that one is a change to screens this task does not touch; this reader
  # takes the name the whole stack is called by instead.
  def holding_calculator(as_of: nil, today: Date.current, net_of_sweep: false,
                         pending: HoldingProjection::Pending.none, terms: nil)
    HoldingProjection.for(
      self, net_of_sweep: net_of_sweep, pending: pending, as_of: as_of, today: today, terms: terms
    )
  end

  # `pending:` threads straight through to the calculator underneath, exactly as it does above: a
  # status is a reading of a balance, so a status of a category that has not yet received this
  # distribution's money is a status of the wrong balance. It is what lets the distribution screen
  # ask "does this envelope still make it if I fund $200 instead of $500" in the app's own
  # vocabulary rather than inventing a second one. `terms:` threads down the same way and for the
  # same reason, and defaults to nothing here too.
  def status(today: Date.current, pending: HoldingProjection::Pending.none, terms: nil)
    HoldingStatus.new(self, today: today, pending: pending, terms: terms)
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

  # `saved_change_to_category_type` IS `[before, after]`, compared as the whole pair rather than
  # asked two questions: with only two types today `expense?` after a type change implies the flip,
  # but a third type added later would make that inference silently wrong, and this callback
  # DELETES money rows.
  #
  # `includes(item: { category: :user })` because `#route_income_to!` reads `user.default_account`
  # through the entry's own chain: the preloader hands every entry of one category the SAME
  # Category and User objects, so the whole loop costs three preloads and one `default_account`
  # lookup instead of three queries per entry.
  def unroute_entries_that_are_no_longer_income
    return unless saved_change_to_category_type == ["income", "expense"]

    entries.includes(item: { category: :user }).find_each { |entry| entry.route_income_to!(nil) }
  end

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

  # THE THREE COLUMNS THAT MAKE A CATEGORY A HOLDER (two-ledger spec §3), in one validator:
  #
  #   * `priority` orders the distribute waterfall. It is NOT NULL with a database default of 0, so
  #     the blank arm only ever fires on a form that submitted an empty string — and a NEGATIVE
  #     priority outranks every category the user meant to fund first. `Pool#priority` carried
  #     exactly this pair of rules for exactly this reason.
  #   * `target_amount` is a goal, and a goal of zero is already met while a negative one is money
  #     owed. Optional: a nil target is "no goal", not a missing value.
  #   * ONLY EXPENSE CATEGORIES HOLD MONEY, so neither `funded_since` nor a target may sit on an
  #     income category. `Allocation` refuses an income category on either side for the same rule;
  #     this is the half that covers the columns rather than the rows. `priority` is deliberately
  #     NOT in that list — every income category in the database already carries the default 0, and
  #     it orders a waterfall an income category is never in.
  #
  # ONE VALIDATOR RATHER THAN THREE `validates` LINES, AND THE FIRST LINE IS WHY. These columns are
  # YOUNGER THAN TWO SPECS THAT PLANT CATEGORIES THROUGH THIS MODEL: `spec/migrations/cutover_spec.rb`
  # and `spec/seeds_spec.rb` rewind the schema past `CategoriesHoldTheMoney` for the length of a
  # file — the only way to hand `DropCapEraBudgetColumns#down` a `budgets.category_id` to restore —
  # and a validator that reads a column the database does not currently have raises NoMethodError
  # out of `valid?`, which is not a rejection of anything. The guard is asked ONCE here instead of
  # three times as an `if:` on three declarations.
  def holding_columns_are_sane
    return unless has_attribute?(:priority)

    priority_is_a_fill_order
    target_is_a_goal
    only_expenses_hold_money
  end

  def priority_is_a_fill_order
    return errors.add(:priority, "can't be blank") if priority.blank?

    errors.add(:priority, "must be greater than or equal to 0") if priority.to_i.negative?
  end

  def target_is_a_goal
    return if target_amount.blank?

    errors.add(:target_amount, "must be greater than 0") unless target_amount.to_d.positive?
  end

  def only_expenses_hold_money
    return if expense?

    errors.add(:base, "only expense categories hold money") if funded_since.present? || target_amount.present?
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
