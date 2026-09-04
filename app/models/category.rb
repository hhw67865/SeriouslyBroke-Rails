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

  # THE COLOUR A CATEGORY HAS WHEN IT HAS NONE, and the ONE spelling of it. The brand sage was
  # written out as a literal `"#C9C78B"` in four places — the index card's chip, the show page's
  # banner, and the form's swatch and its hex readout — each guarding with `category.color ||`.
  #
  # `||` WAS THE BUG (design review H3). The form's colour radios ship no default, so a user who
  # never touched them submitted `color: ""` — and an empty string is not nil, so every one of
  # those guards passed it straight through to `background-color: ;`. The chip rendered as a
  # transparent hole and the banner's icon as a white heroicon on white. `#display_color` is the
  # reader all four now go through, and `presence` is what makes `""` mean "unset" the way the
  # form has always meant it.
  DEFAULT_COLOR = "#C9C78B"

  belongs_to :user, touch: true

  # `belongs_to :pool` IS GONE WITH `categories.pool_id` (two-ledger spec §5, Task 8). Where a
  # category's spending LANDED was the pool era's question; under the two-ledger model the category
  # holds its own money (§2) and spending drains the category from `funded_since` on and AVAILABLE
  # before it. `#pool_must_be_reachable`, `#income_must_land_in_an_account`, `#effective_pool` and
  # `#buffer_funded?` are gone with it — every one of them was an answer about a lane.

  has_many :items, dependent: :destroy
  has_many :entries, through: :items

  # THE RULES THIS CATEGORY IS FUNDED BY (two-ledger spec §3): `budgets.category_id` replaces
  # `budgets.pool_id`, one category to one budget line. `dependent: :destroy` because a rule with
  # no category to fund is a demand on the waterfall for money nothing can hold.
  has_many :budgets, dependent: :destroy

  # ** `allocations_in` AND `allocations_out` ARE GONE WITH THE TABLE (computed-claims spec §5). **
  # They were the two sides of the purpose ledger, `dependent: :destroy` so that destroying a
  # category that had ever held money did not raise on a foreign key. Nothing moves on the purpose
  # side any more: a category's money is `#claim`, computed from its rules, so there is no row to
  # cascade and no holding to give back. What a destroyed category's rules take with them is
  # `has_many :budgets, dependent: :destroy` above, and their adjustments follow from
  # `Budget has_many :adjustments, dependent: :destroy`.

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

  # WHAT TO PAINT THE CHIP, THE BANNER AND THE FORM'S SWATCH. See DEFAULT_COLOR for why a blank
  # is not merely absent here but actually reachable from the form.
  def display_color = color.presence || DEFAULT_COLOR

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }

  # ** THE GIVE-WAY ORDER, AND THE ONE PLACE IT LIVES (computed-claims spec §4). ** It was the
  # order the distribute waterfall FILLED in; there is no distribution and nothing to fill, and
  # §4 keeps the column for the job it can still do: when a user's claims outrun their money,
  # `HomePresenter#uncovered_claims` walks this order BACKWARDS and names the categories nothing
  # covers, lowest priority giving way first. The Budget page's drag-reorder writes it
  # (`.apply_fill_order`), and the scope's NAME is kept because both readers spell it this way and
  # a rename would put a diff over them for a word.
  #
  # HOLDERS ONLY, which is `expense? && funded_since.present?` — `Category#holder?` in SQL. An
  # income category can hold no claim (`Budget#category_must_be_an_expense`), and an expense
  # category that has never been funded is one whose spending counts against nothing
  # (`CategoryLedger::ENTRY_CATEGORY_ID`'s own NULL arm).
  #
  # `[priority, name]`, ON `Pool.by_priority`'S OWN REASON: priority alone is not a total order, and
  # a tie falling through to database order means random UUID bytes deciding which category gives
  # way first. `name` is unique per user, so the pair is total.
  scope :in_fill_order, -> { expenses.where.not(funded_since: nil).order(:priority, :name) }

  # THE CATEGORIES THE BUDGET PAGE DRAWS A CARD FOR — the ones a rule actually fills. `Pool
  # #in_fill_order` was this set on the pool side (`joins(:budgets).distinct`) and the name is taken
  # here by the WATERFALL's set, which is wider: a goal fed only by hand holds money and is in the
  # fill order without any rule naming it.
  #
  # A SUBQUERY RATHER THAN `joins(:budgets).distinct`, and that is not a style choice.
  # `Pool#in_fill_order`'s own comment records the trap: `SELECT DISTINCT` refuses an ORDER BY over
  # a column the narrowed select list does not carry, so `.in_fill_order.with_a_rule.ids` — which
  # is exactly what `.apply_fill_order` asks below — would raise `PG::InvalidColumnReference`
  # against a scope that composes perfectly well everywhere else. An `IN (SELECT category_id …)`
  # has no such edge, and a NULL inside an `IN` list simply never matches (it is `NOT IN` that
  # would be the hazard).
  scope :with_a_rule, -> { where(id: Budget.where.not(category_id: nil).select(:category_id)) }

  # THE LATCH ITSELF, CASE-INSENSITIVE — matching, not merely resembling, the `uniqueness:
  # { case_sensitive: false }` validation above. An exact-case `where(name: OPENING_BALANCE_NAME)`
  # would miss a category a user already named "opening balance" through the ordinary categories
  # screen: the latch would read "not yet recorded" while `create!` below collided with it on the
  # very uniqueness rule this scope has to agree with, turning an onboarding click into a crash.
  # Same spelling `Item#move_to_category` already uses for the same reason.
  scope :opening_balance, -> { where("LOWER(name) = ?", OPENING_BALANCE_NAME.downcase) }

  # `:budget` LEFT THE EXPENSE PRELOAD with the cap card it fed, and `:pool` left it with the column
  # (Task 8): the Categories index prints what a category HOLDS now, which is read off the category
  # itself and its allocations.
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
          else expenses.includes(:items)
          end
        }

  # Configure searchable fields
  searchable :name, label: "Name"

  # THE FILL ORDER, WRITTEN (two-ledger spec §2) — the port of `Pool.apply_fill_order`, and the only
  # writer for `categories.priority` outside the category form. `category_ids` is the user's
  # rule-carrying holders in the order they were just dragged into. Answers the USER on success and
  # NIL on refusal, which is the whole vocabulary the caller needs: nothing partial exists.
  #
  # THE SCOPE IS THE USER, WHERE THE POOL ERA'S WAS ONE ACCOUNT, and that is the model change rather
  # than a simplification. Priority used to be compared only inside an account because the fill was
  # per-account (`account.child_pools.by_priority`); `AllocationCalculator` now walks
  # `Category.in_fill_order` over ONE root, so every holder is ranked against every other and there
  # is exactly one list on the page to drag.
  #
  # DENSE, not "shift the moved row and leave the rest": `in_fill_order` is `[priority, name]`, so a
  # sparse rewrite leaves ties whose winner is decided by a name — the defect Plan 1 shipped in its
  # waterfall. The rewrite is dense over the user's WHOLE holder set, not merely over the submitted
  # ones, and each unsubmitted holder KEEPS ITS PLACE in the sequence: a savings goal with no rule
  # draws no card and would otherwise be left on an old number colliding with a renumbered one, and
  # the tie-break the density exists to defeat would decide which of the two gets funded first. Its
  # number moves, its rank does not.
  #
  # EVERY REFUSAL IS THE SAME REFUSAL and writes nothing at all:
  #   * an id that is not this user's (`user.categories` is the only lookup, so a stranger's id
  #     simply is not found and the size falls short),
  #   * a duplicate id (which would make the list shorter than it looks and silently drop one),
  #   * a list that is not the user's whole `in_fill_order.with_a_rule` set — a page whose rules
  #     have changed under it, submitting an order for categories that are no longer the ones being
  #     ordered. Nothing is written and the page comes back saying so.
  #
  # TWO REORDERS AT ONCE ARE LAST-WRITE-WINS, AND THAT IS A DECISION RATHER THAN A LEAVING.
  # `user.lock!` is the first statement inside the transaction, exactly as `account.lock!` was and
  # for the same reason: without it two tabs issue their UPDATEs in their own submitted orders, take
  # the same rows in DIFFERENT orders, and Postgres breaks the cycle by killing one with a deadlock
  # — a 500 on a button click. Serialised behind the user row, the second reorder lands on top of
  # the first, whole. The staleness check is INSIDE the lock for the same reason: a rule deleted
  # between the check and the write would otherwise slip past a guard that had already passed.
  #
  # Nothing here rescues. `update!` runs the full validation stack on every row, deliberately — this
  # is the only writer for `priority` and a reorder must not be the request that sneaks an invalid
  # row past the model — so a row that was ALREADY invalid raises RecordInvalid, the transaction
  # rolls back, and BudgetPageController#reorder turns it into the same 422 as every other refusal
  # with the offending row named.
  def self.apply_fill_order(user:, category_ids:)
    ids = Array(category_ids).map(&:to_s)
    categories = fill_order_categories(user, ids)
    return if categories.nil?

    transaction do
      user.lock!
      next unless user.categories.in_fill_order.with_a_rule.ids.map(&:to_s).sort == ids.sort

      write_fill_order(user, ids, categories)
      user
    end
  end

  # The submitted categories dropped into the slots the submitted categories already hold,
  # everything else left where it stands, and the whole holder set renumbered 0,1,2… off the result.
  def self.write_fill_order(user, ids, categories)
    queue = ids.dup
    user.categories.in_fill_order
      .map { |category| categories.key?(category.id.to_s) ? categories.fetch(queue.shift) : category }
      .each_with_index { |category, index| category.update!(priority: index) }
  end
  private_class_method :write_fill_order

  # The submitted categories keyed by their id as it arrived on the wire, or NIL if the list itself
  # is not a list of this user's categories: empty, holding a duplicate (which would make it shorter
  # than it looks and drop one), or naming an id `user.categories` does not find — someone else's,
  # or nothing at all, and the two deserve the same answer.
  def self.fill_order_categories(user, ids)
    return if ids.empty? || ids.uniq.size != ids.size

    categories = user.categories.where(id: ids).index_by { |category| category.id.to_s }
    categories if categories.size == ids.size
  end
  private_class_method :fill_order_categories

  # DOES THIS CATEGORY HOLD MONEY? (two-ledger spec §3.) Two facts and no third: only an EXPENSE
  # category can hold — income lands in available and is allocated out of it — and it holds from
  # `funded_since` onward, the date it first got a rule or an allocation. A category with no
  # `funded_since` has never been given money to hold, so its spending drains available.
  #
  # This is the predicate every screen asks where it used to ask `pool.pool_type_budget?`.
  def holder? = expense? && funded_since.present?

  # ** THE STAMP THAT MAKES A CATEGORY START HOLDING (§4), SPELLED ONCE (final fix wave, I-1). **
  # §4's own sentence names TWO events — "the date it first got a rule OR AN ALLOCATION" — and only
  # the rule path ever wrote the date: `BudgetProposal#start_holding` stamped it beside a new rule,
  # and the hand-allocation path wrote money into a category and left `funded_since` NULL. What that
  # produced was money nothing could see: the category is absent from `Category.in_fill_order` and
  # from every holder population, its show page said "doesn't hold money yet" over the balance, and
  # the reallocation picker offered no way to move it back out. Both callers come here now, so the
  # rule cannot drift into two spellings of "when does a category start holding".
  #
  # A NO-OP ON A CATEGORY THAT IS ALREADY HOLDING, which is the whole reason it is a method rather
  # than an `update`: re-stamping to today would silently push the start date FORWARD and hand the
  # category's own recent spending back to available. The second rule in a category, and every
  # allocation after the first, take this arm.
  #
  # `today` IS THE DEFAULT AND THE CALLER MAY NAME IT, on `BudgetProposal`'s reasoning: a category
  # starts holding the moment the user says so, which is now, and earlier spending stays where it
  # physically was. The default is `#today` — the OWNER's calendar day, re-zoned from the user rather
  # than from the ambient clock (fix round 2 — LOW-1) — which is the same day
  # `CategoryLedger::ENTRY_CATEGORY_ID` compares against.
  #
  # TRUE OR FALSE, like the `update` underneath it: a caller that needs to say why reads
  # `errors` off the record, which is what both callers do.
  def start_holding(today: self.today)
    return true if funded_since.present?

    update(funded_since: today)
  end

  # ** `#savings?` IS DELETED (computed-claims spec §3.3), AND ITS THIRD CLAUSE IS WHY. ** It was
  # `holder? && target_amount.present? && budgets.none?` — a goal is a holder with a target and NO
  # RULE — and that clause existed to tell a goal apart from an envelope somebody also set a ceiling
  # on: a category the waterfall refilled every period was being SPENT toward a rate, not SAVED
  # toward a figure.
  #
  # THERE IS NO WATERFALL, AND EVERY CLAIM COMES FROM A RULE. A goal with money in it therefore HAS
  # a rule by construction — a target rule that accrues, or the amount-ZERO shape §3.2 rules is how
  # "no rate" is spelled for a goal fed only by set-asides — so `budgets.none?` selected exactly the
  # goals that claim nothing, and `DropTheDistribution` mints that zero-amount rule for every goal
  # in a real database that lacked one. Its last caller, the dashboard's savings strip, rendered
  # NOTHING on migrated data; it asks `#saving_toward_a_target?` now, which is the same question
  # without the clause that inverted.

  # THE RUBY MIRROR OF `CategoryLedger::ENTRY_CATEGORY_ID`, and the ONLY one (Task 2's global
  # constraint): every other reader in this app asks the SQL. Spending counts against this category
  # from `funded_since` onward, compared in the OWNER's calendar day — `#local_day` is the same
  # re-zoning the SQL does with its two `AT TIME ZONE`s, so a Tokyo user's Aug 1 entry, stored
  # `2026-07-31 15:00` UTC, counts on Aug 1 wherever this runs.
  def counts_spending_on?(date)
    holder? && local_day(date) >= funded_since
  end

  # WHAT THIS CATEGORY'S MONEY IS (computed-claims spec §2): the SUM OF ITS RULES' CLAIMS, and
  # nothing else. There is no balance here to read and nothing was ever moved into this record — a
  # category's money is a function of its rules, the calendar, its spending and its adjustments, so a
  # category with no rules claims nothing however much has been spent against it (§3.4: an unbudgeted
  # category with spending shows `spent $X`, which is a fact about entries rather than a claim).
  #
  # `sum(0.to_d)` with an explicit BigDecimal seed, on `Budget.steady_need`'s reason: an empty
  # relation's `sum` is the Integer `0`, and this figure is subtracted from a user's total money.
  #
  # UNBATCHED, DELIBERATELY, exactly as `Category#holding_calculator` is: one category is a handful
  # of queries whether they are grouped or not. A screen iterating categories builds a `ClaimLedger`,
  # which is the batched door and which pins itself against this one figure for figure.
  def claim(today: self.today)
    budgets.sum(0.to_d) { |budget| budget.claim_calculator(today: today).claim }
  end

  # A DATE NO RULE CAN BE DUE ON, so an undated rule sorts last without the key carrying a nil that
  # `<=>` cannot compare.
  NEVER_DUE = Date.new(9999, 12, 31)

  # ** THE ORDER A CATEGORY'S RULES ARE LISTED IN — ONE SPELLING (fix wave — LOW-3). ** Three screens
  # render §3.4's line per rule and each had written its own key: `BudgetPagePresenter#rule_order`
  # and `CategoryBudgetPresenter#line_order` agreed on this one, and `HomePresenter#claim_lines`
  # sorted by `[item name, id]` instead — so one category's rules appeared in one order on Home and
  # another on the Budget page, and a user comparing the two screens read two lists.
  #
  # ** THE TWO-SCREEN KEY WINS, AND HOME'S ARGUMENT IS THE WEAKER ONE. ** Home's was that the
  # item-less rule leads because it is the category's own envelope and the item-backed ones are
  # exceptions carved out of it (§3.1's lane partition) — a real thought, but a preference about
  # emphasis. This key is ordered on the DATE THE ROW PRINTS, which is a fact the reader can see:
  # what is due soonest is first, and a rule with no date at all (a rate rule is never due) sorts
  # last. That is the ordering a person scanning for what needs attention actually wants, and it is
  # already the one two of the three screens use.
  #
  # ** IT IS TOTAL, and every term earns its place. ** `budgets` carries no ORDER BY and a plain
  # UPDATE relocates a row in the heap, so without a total key two rules could swap places between
  # page loads with no data change. `-amount` breaks a shared due date toward the LARGER obligation
  # — the bigger bill is the one you can least afford to be short on — and the id makes even
  # identical amounts deterministic.
  #
  # `next_due_on` IS THE CLAIM'S OWN READING (`ClaimCalculator#next_due_on`) at every caller, which
  # is the date the row prints: ordering by one date and printing another would put a row above its
  # neighbour for a reason the screen contradicts. `amount.to_d` because an in-memory record
  # assigned `amount: 180` holds the Integer, and a key mixing Integer with BigDecimal across a
  # comparison depends on where the row came from.
  #
  # ON `Category` because a rule's order is a fact about the SET one category holds — the three
  # callers each sort the lines of exactly one category — and this is the record that owns that set.
  def self.rule_order(next_due_on:, amount:, id:)
    [next_due_on.present? ? 0 : 1, next_due_on || NEVER_DUE, -amount.to_d, id]
  end

  # ** IS THIS ROW A GOAL — THE DISPLAY QUESTION (computed-claims spec §3.4). **
  # `HoldingCalculator#saving_toward_a_target?` re-homed, and it was always this expression: a holder
  # with a figure to reach. It REPLACED `#savings?`, which additionally required the category to
  # carry NO rule — a goal the user also refills at a rate (the demo's Retirement Supplement) is
  # still a goal to look at, and under §3.3 a goal with money in it always HAS a rule, so that
  # clause selected exactly the goals claiming nothing. See its tombstone above.
  #
  # THE FOUR SCREENS THAT ASK IT — the categories index card, the categories page's holdings card,
  # the entry form's impact card and the dashboard's savings strip — ask it here, so a rule-bearing
  # goal is a goal on every one of them; this is that question asked of the category a screen is
  # drawing.
  #
  # ** THE COLUMN THIS READS IS ON ITS WAY OUT (rules-own-the-budget spec §5/§7). ** A goal is a
  # BUILDING RULE with a target now, and `ClaimCalculator#shape` no longer consults this record at
  # all — it answers `:building` off the rule's own `carries_over`. The four screens above still ask
  # here, so the column and this reader survive until the screens task moves them; nothing in the
  # claim formulas reads either any more.
  def saving_toward_a_target? = holder? && target_amount.present?

  # ** IS ANYTHING BUDGETED HERE — THE ONE SPELLING, SHARED BY HOME AND THE ENTRY FORM (fix round
  # 1 — M2). ** Every claim comes from a rule (§3.3), so "budgeted" is exactly "carries a rule": a
  # category with none claims nothing however much has been spent against it, and §3.4's own
  # sentence for that shape is `spent $X` with no bar and no envelope.
  #
  # IT WAS TWO PREDICATES AND THEY DISAGREED ON A REACHABLE SHAPE. `HomePresenter::PeriodRow
  # #budgeted?` asked `lines.any?` — one line per rule — while `EntryImpactPresenter#unbudgeted?`
  # asked `holding.nil?`, and `#holding` is the category whenever `#counts_spending_on?`. Under the
  # pool layer those agreed, because a funded category was one money had been moved INTO; under
  # computed claims a FUNDED category with no rules is an ordinary shape (the Budget page's rate
  # suggestion offers a rule to exactly that population). So the card drew it an envelope claiming
  # $0.00, made `balance_after` `−amount`, and painted it danger red with an overdraw notice, while
  # Home called the same category unbudgeted an inch away.
  #
  # `budgets.load.any?`, AND THE `load` IS MEASURED RATHER THAN DECORATIVE. Both callers read the
  # rules themselves straight afterwards — Home eager-loads `:budgets` for its lines, and the impact
  # card reads the same association twice more (`#steady_claim`, `#claim_calculators`) — and bare
  # `any?` on an UNLOADED association is `exists?`, which emits `SELECT 1 … LIMIT 1` and then leaves
  # the full load still to pay for. Measured on the entry card: 5 statements that way against 4 with
  # the load, for the identical answer. `load` is a no-op where the association is already there, so
  # Home pays nothing for it.
  #
  # NOT `#holder?` AND NOT `#counts_spending_on?`. Those are about the CATEGORY's funding date —
  # whether this receipt's day is one whose spending counts — and they remain the gate in front of
  # this one on the entry card (`#holding`). A category can be funded and unbudgeted, or budgeted
  # and asked about a day before it was funded; the two questions are independent and both are asked.
  def budgeted? = budgets.load.any?

  def calculator(date = today, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  # ** `#holding_calculator` AND `#status` ARE GONE (computed-claims spec §6). ** They were the one
  # door onto what a category HELD and the reading of that balance in the row vocabulary
  # (`HoldingCalculator`, `HoldingStatus`, `HoldingProjection`, all deleted). Both answered a
  # question about MOVED money — allocations in, less allocations out, less the spending — and there
  # is no such money. `#claim` above is the door now, `ClaimCalculator` is the reading, and its
  # `#over?`/`#overdue?` carry the two states of the old seven that survive the change of model.

  # THE OWNER'S TODAY, reached the same way every other day on this record is (fix round 2 — LOW-1).
  # `User#today` carries the whole argument for why this is not `Date.current`; what this reader adds
  # is the OWNER-LESS arm, which it gets for free by going through the private `#local_day` — the
  # same fallback to UTC that method already documents, rather than a second policy for an unsaved
  # category.
  #
  # PUBLIC, THOUGH `#local_day` IS NOT: it is the default for every `today:` this class hands down
  # (`#start_holding`, `#claim`, `#calculator`) and it is what `Budget#today` reaches through, so a
  # caller that names no day gets the owner's.
  def today = local_day(Time.current)

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

  # THE CALENDAR DAY AN INSTANT FELL ON, IN THE OWNER'S ZONE — the Ruby half of ENTRY_LOCAL_DAY's
  # `AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(category_users.timezone, 'UTC')`, delegated to
  # `User#local_day` where the rule now lives (the claims work gave it a second and a third caller —
  # `Adjustment#local_day` and `ClaimCalculator`). What stays here is the OWNER-LESS arm alone: a
  # category is `belongs_to :user` and the column is NOT NULL, so it is reachable only from an
  # unsaved record, and re-zoning by nothing is the same answer the SQL's `COALESCE(…, 'UTC')` gives.
  def local_day(moment)
    return user.local_day(moment) if user

    moment.is_a?(Date) && !moment.is_a?(DateTime) ? moment : moment.in_time_zone("UTC").to_date
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
  # YOUNGER THAN THE MIGRATION SPECS THAT PLANT CATEGORIES THROUGH THIS MODEL:
  # `spec/migrations/cutover_spec.rb` and `spec/migrations/two_ledger_spec.rb` rewind the schema past
  # `CategoriesHoldTheMoney` for the length of a file, and a validator that reads a column the
  # database does not currently have raises NoMethodError out of `valid?`, which is not a rejection
  # of anything. The guard is asked ONCE here instead of three times as an `if:` on three
  # declarations.
  #
  # `spec/seeds_spec.rb` WAS ON THAT LIST UNTIL TASK 8 and is not any more: the seeds are
  # category-native, so there is no schema they can be replanted against but the current one.
  def holding_columns_are_sane
    return unless has_attribute?(:priority)

    priority_is_a_fill_order
    target_is_a_goal
    funding_start_is_not_in_the_future
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

  # A FUNDING START IN THE FUTURE IS SCHEDULING, AND NOTHING IN THIS APP SCHEDULES (fix round 1,
  # LOW-1). `funded_since` is the day a category begins counting its own spending, and every reader
  # of it treats "set" as "counting now": `Category#holder?` asks only that the column is present,
  # so `AllocationCalculator` puts a future-dated category straight into the fill order and a
  # distribution funds it TODAY — while `CategoryLedger::ENTRY_CATEGORY_ID` goes on reading its
  # spending against AVAILABLE until the date arrives. Money in the category, spending out of the
  # root, and no screen saying why. Accepted silently, it is a shape the two-ledger invariant
  # survives (§2 holds either way) but no user could ever explain.
  #
  # REFUSED RATHER THAN COERCED to today: a user who typed next month meant something, and quietly
  # writing a different date is the class of lie the branch has been removing. The message says what
  # to do instead.
  #
  # THE COMPARISON IS THE OWNER'S DAY, through `#local_day` — the same re-zoning
  # `#counts_spending_on?` and `ENTRY_CATEGORY_ID` use, so a Tokyo user filling in their own
  # calendar's today is not told it is tomorrow. TODAY ITSELF IS FINE: a category funded this
  # morning counts this morning's spending, which is the ordinary shape of setting one.
  def funding_start_is_not_in_the_future
    return if funded_since.blank?
    return if funded_since <= local_day(Time.current)

    errors.add(
      :funded_since,
      "can't be in the future — a category starts holding money on the " \
      "day you give it some, so set today or a past date"
    )
  end

  # ** `#money_may_not_be_stranded` IS GONE, AND SO IS THE STATE IT REFUSED (computed-claims spec
  # §5). ** It stopped a user clearing `funded_since` on a category still carrying allocations: the
  # money stayed exactly where it was while every reader of `holder?` stopped looking at it, and no
  # screen in the app could move it back out. There are no allocations. A category holds nothing to
  # strand — its money is `#claim`, a function that simply answers differently once the column
  # changes — so the shape the validator existed to make unreachable cannot be reached.
  #
  # WHAT CLEARING `funded_since` DOES NOW, said plainly because it is not nothing: the category
  # leaves `#in_fill_order` and every holder population, and `CategoryLedger::ENTRY_CATEGORY_ID`
  # stops attributing its spending to it — so a rate rule on it reads its full claim with the
  # spending ignored. That is a visible, recoverable state on a screen that names it (the Budget
  # page's "not filling" band, and Home renders those categories for Task 3's ruling 9), not money
  # nobody can reach. `#funded_since_in_database`, which existed only to gate this validator's
  # queries, goes with it.

  # THE PRESENCE ERROR WINS (design review H3). `expense?` is false for a category whose type is
  # BLANK as well as for an income one, so a user who filled the form in and simply never picked a
  # type was told "only expense categories hold money" — a sentence about a choice they had not
  # made, on a form whose only real fault was the unanswered question two cards above. Two errors
  # were rendered and the wrong one read as the cause.
  #
  # The blank case already has its own message from `validates :category_type, presence: true`, and
  # this validation has nothing to add until there is a type to disagree with.
  def only_expenses_hold_money
    return if category_type.blank? || expense?

    errors.add(:base, "only expense categories hold money") if funded_since.present? || target_amount.present?
  end
end
