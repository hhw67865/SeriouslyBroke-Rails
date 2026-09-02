# frozen_string_literal: true

class Pool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true

  # `dependent: :nullify` IS GONE, AND IT WAS A LIVE TRAP RATHER THAN A BACKSTOP (plan 3 task 6,
  # the decision task 3 handed forward). It issued `update_all` over `Category.where(pool_id: id)`,
  # which walks straight past the required `belongs_to :pool` and past
  # `income_must_land_in_an_account`: destroying a pool wrote NULL `pool_id`s that no validation
  # would have allowed, and `ENTRY_POOL_ID`'s `COALESCE(entries.pool_id, categories.pool_id)` then
  # resolved every entry those categories carried to NOTHING — `Σ pools` rising by the pool's
  # lifetime spending while the bank had obviously paid it.
  #
  # THE REAL DESTROY ORDER, TRACED RATHER THAN ASSUMED, is why the replacement is a refusal and not
  # a second re-point:
  #
  #   * an ENVELOPE or GOAL never reaches this callback with a category still pointing at it.
  #     `#return_holdings_to_the_account` is `prepend: true`, so it runs FIRST, and it either
  #     re-points every category to the user's MAIN account (`#hand_categories_to_the_account` —
  #     main-account spec §6 rewrote this from "the pool's own account" after a category on a
  #     non-main envelope's account raised `ActiveRecord::RecordInvalid` straight through
  #     `PoolsController#destroy`, a production 500) or refuses the destroy outright. By the time
  #     this dependency is consulted the scope is empty — which the old comment on
  #     `#hand_categories_to_the_account` already recorded, measured: dropping its `reset` failed
  #     nothing, because nullify never had a row to find.
  #   * an ACCOUNT returns from that callback on its first line (`return if pool_type_account?`).
  #     It has no account of its own to absorb anything, so there was nowhere to re-point to and
  #     the nullify fired for real. That is the one case the option ever ran in, and it ran
  #     wrongly.
  #
  # So the option is unreachable where it would have been harmless and harmful where it was
  # reachable, and it is REPLACED rather than left standing. `restrict_with_error` is the pattern
  # `#child_pools` already uses one screen away: an error on `:base`, a halted callback chain, and
  # PoolsController#destroy rendering it through the branch that already exists for an account
  # holding pools. An account whose categories still point at it refuses to be deleted, and the
  # user moves them somewhere first — there is no other honest answer, because a category must
  # name a pool and this app cannot guess which of the user's other accounts should inherit one.
  #
  # It costs the envelope path one `SELECT COUNT(*)` that answers zero. `#empty?` re-queries
  # because `#hand_categories_to_the_account` resets the association, so the count sees the
  # re-pointed world rather than the loaded target.
  has_many :categories, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items

  # Entries that named this pool directly, overriding their category's. Nullified on destroy so
  # the entry FALLS BACK DOWN THE CHAIN — `ENTRY_POOL_ID` is
  # `COALESCE(entries.pool_id, categories.pool_id)`, so clearing the override hands the entry to
  # its category's pool — rather than blocking the delete on a foreign key.
  #
  # NOT "for the same reason categories are", WHICH TASK 8 REVERSED AND PLAN 3 TASK 6 FINISHED.
  # Categories are not nullified at all any more: `#return_holdings_to_the_account` re-points them
  # to the destroyed pool's account before the association's own callback can fire, and the
  # callback itself is now `restrict_with_error` — precisely because nullifying them took every
  # entry they carried out of the pool tree and raised `Σ pools` by the pool's lifetime spending.
  # This line is a different case with a different answer, and citing that one as its reason is
  # now backwards.
  #
  # WHY THIS ONE IS STILL A NULLIFY when its sibling became a refusal: `entries.pool_id` is an
  # OVERRIDE of a value the entry already has by another route, so clearing it hands the entry
  # back to its category's pool rather than to nothing. `categories.pool_id` is the only answer
  # its row has, so clearing that one is the deletion of a fact. The residual below is the one
  # shape where the two coincide.
  #
  # THE RESIDUAL, RECORDED HERE RATHER THAN ONLY IN THE SDD LEDGER, AND NARROWED TWICE SINCE: an
  # override entry whose CATEGORY points at no pool would leave the tree. Clearing
  # `entries.pool_id` makes `ENTRY_POOL_ID` `COALESCE(NULL, NULL)` — NULL — so that entry counts
  # toward no pool at all and `Σ pools` rises by its amount, the same shape Task 8 fixed for
  # categories. Plan 3 decision 3 made `belongs_to :pool` REQUIRED on `Category`, and task 6
  # replaced the one writer that walked past it (`dependent: :nullify` on `#categories`, which
  # reached `update_all`), so nothing in the app can produce the pool-less category this residual
  # needs. `categories.pool_id` is still nullable AT THE DATABASE — the remaining tightening, named
  # in the task 6 report — so the residual is a Ruby-level impossibility rather than a structural
  # one. It was already unreachable from the UI, and that was grepped rather than assumed:
  # `EntriesController#entry_params` permits
  # `[:amount, :date, :description, :item_id]` and nothing else, so no request can set
  # `entries.pool_id` at all, and no other writer of it exists in `app/`. The column is a schema
  # affordance the UI has not yet grown into. The honest fix, when something can reach it, is the
  # one the categories half already got — re-point the override to this pool's account inside
  # `#return_holdings_to_the_account` rather than clearing it.
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

  # ONE NOUN PER POOL TYPE, IN ONE PLACE, because three screens had three of them for one pool.
  #
  # THE DEFECT (2d whole-plan review, fix 2). For the demo's Health → Emergency Fund shape — an
  # EXPENSE category pointing at a SAVINGS pool — the category page's budget block called it an
  # "Envelope", the pool card four inches below called it a "Savings Pool", and the entry form's
  # impact card called it a "goal". Three nouns, one pool, one afternoon. The CLASSIFIERS never
  # disagreed — every one of them resolves `pool_type_*` — only the words did, which is precisely
  # the shape a shared classifier cannot catch.
  #
  # `entries/_impact` IS THE MODEL the other two were moved onto: it already said "goal" for a
  # savings pool and "buffer" for an account, and those are the words the rest of the app's prose
  # uses for the same things (`home/_account`'s "buffer now", `PoolCalculator#dateless_goal?`,
  # spec §7.1's buffer marker). So the vocabulary was not invented here; it was collected.
  #
  # ON THE MODEL RATHER THAN IN A HELPER, for one reason: `EntryImpactPresenter` is a PORO that
  # needs this noun and cannot reach a view helper without including ActionView, and a second
  # spelling of the mapping for the presenter's sake would be exactly the drift this constant
  # exists to close. It is a fact about the pool's TYPE, not about a screen — every screen that
  # capitalises or pluralises it does so at the call site.
  #
  # `fetch`, so a fourth pool type raises here rather than defaulting quietly to "envelope" on
  # three screens at once.
  NOUNS = { "account" => "buffer", "budget" => "envelope", "savings" => "goal" }.freeze

  def noun = NOUNS.fetch(pool_type)

  # THE TWO DESTROYS THIS MODEL REFUSES, both refusing in the same vocabulary
  # `dependent: :restrict_with_error` does — an error on `:base` and a halted callback chain — so
  # PoolsController#destroy renders them through the branch that already exists for an account
  # holding pools. See #return_holdings_to_the_account, their only reader.
  #
  # Two reasons rather than one, because the two are fixed differently: a pool whose CATEGORIES
  # have nowhere to go needs an account of its own, while a pool whose TRANSFERS have nowhere to go
  # names a counterparty that is itself account-less, and either end being housed resolves it.
  # Nullifying instead is the `Σ pools` break this fix round exists to refuse, so it is refused
  # here rather than absorbed silently.
  #
  # BOTH ARE UNREACHABLE SINCE PLAN 3 TASK 6, AND THE REASON GIVEN HERE FOR KEEPING THEM WAS WRONG
  # — corrected rather than quietly deleted, because the wrong version is the kind that gets
  # believed. Every branch below turns on a non-account pool whose `account` is BLANK, which
  # `#account_matches_pool_type` refuses and `CHECK ((pool_type = 0) = (account_id IS NULL))`
  # refuses again past the model, and the five examples that covered them are deleted with their
  # reason in `spec/models/pool_destroy_spec.rb`.
  #
  # THE WITHDRAWN CLAIM was that they are worth holding as a net for "whatever a future import,
  # backfill or console session writes". A CHECK constraint is not a validation: it holds against
  # `update_all`, against a fixture and against a console alike, so the shape these test —
  # `account_id IS NULL` on a non-account — is not something a console CAN write. What a console
  # can still write is the MIS-HOUSED pool: an `account_id` naming an envelope or a stranger's
  # account, which no CHECK can refuse (the rule needs a subquery; see #account_is_this_users_
  # account). That row's `account` is PRESENT, so it satisfies every branch below and these
  # backstops do not catch it — they are a net over the one hole the database already covers and
  # not over the one it leaves.
  #
  # AND NOTHING ELSE NAMES IT EITHER, WHICH IS THE POINT. `#account_matches_pool_type` refuses a
  # NEW one at the model, and `CutoverToEnvelopeBudgeting#house_the_pools` re-housed the ones that
  # existed at the cutover — SILENTLY, in the default account, which is a repair rather than a
  # report — with the verifier's "is not an account of this user" arm behind it. None of those is
  # available to a row written after the cutover: the migration has run, and no pre-flight of it can
  # see a console session that comes later. (`#misfiled_account_failures`, the one pre-flight in the
  # neighbourhood, asks the MIRROR question — an ACCOUNT carrying a parent — and never looks at a
  # non-account pool at all.) So the mis-housed pool is a shape the app refuses at its front door,
  # repairs nowhere, and reports through no screen. That is an argument for the deletion follow-up
  # below rather than for keeping these two, which do not help with it.
  #
  # SO THEY STAY FOR THE HONEST REASON: they are retained pending the follow-up that deletes the
  # whole orphan apparatus, not as a guard against anything. That follow-up is larger than this
  # constant and its blast radius is written down so it can be scoped rather than rediscovered:
  # these two refusals and `#absorbing_account_for`'s counterparty fallback here.
  #
  # EVERY OTHER ITEM ON THAT LIST IS NOW DELETED, and it is worth recording which task took which:
  # `BudgetPagePresenter#orphan_rules`/`#orphan_reason` and the Budget page's own orphan band went
  # in Task 5; `ReallocationPresenter` was written in Task 4 with no "No account" group to inherit;
  # and Task 6 took Home's whole half — `#orphan_pools`, `#orphan_required`, `#orphan_pools_owed`,
  # `Row#orphan`, the waterfall exclusion, the `home/_orphans` partial, the `orphan_pools_owed`
  # term in `home/_attention` and `HomeHelper#pool_problem_label`'s `orphan:` keyword. What is left
  # is this constant and the fallback beside it, and they die with the pool layer in Task 8.
  # `:categories` COVERS TWO SHAPES NOW (main-account spec §6): the orphan one this refusal was
  # written for (the pool itself sits in no account) and one that arrived with the re-point
  # destination change — the user has no MAIN account named for a category to land in instead.
  # One sentence covers both rather than two, because both are the same user-facing fact: there
  # is nowhere for this pool's categories to go, and the fix is naming an account either way.
  REFUSALS = {
    categories: "can't be deleted while categories point at it and there's nowhere for their " \
                "spending to land — either it sits in no account itself, or you have no main " \
                "account named. Assign it to an account, or nominate a main account, first.",
    movements: "can't be deleted while it holds transfers and sits in no account — there is no " \
               "buffer for its money to return to. Move it, or the pool on the other end of " \
               "those transfers, into an account first."
  }.freeze

  # Named `*_pools` so they can never be misread as the `budgets` association
  # (`pool.budgets` holds Budget records; `Pool.budget_pools` holds Pool records).
  scope :accounts, -> { where(pool_type: :account) }
  scope :budget_pools, -> { where(pool_type: :budget) }
  scope :savings_pools, -> { where(pool_type: :savings) }
  scope :by_priority, -> { order(:priority, :name) }

  # THE POOLS A FUNDING RULE MAY BE OWNED BY — an envelope or a savings goal, never an account.
  # `Budget#pool_must_not_be_an_account` is the same fact stated as a refusal, and this is the
  # positive form the hand-made rule form's picker offers (Henry's ruling of 2026-08-20). The two
  # are deliberately not the same code: the validation is the law, and a picker that merely agreed
  # with it by hand would be free to drift the day a fourth pool type lands.
  #
  # Not `budget_pools.or(savings_pools)`, which is the same set spelled as the complement of the
  # one type that matters — this says what it means, and it will keep meaning it if a type is
  # added that a rule CAN own.
  scope :rule_owners, -> { where.not(pool_type: :account) }

  # `scope :in_fill_order` AND `.apply_fill_order` ARE DELETED (two-ledger spec §2/§5, Task 5). They
  # were the set an account's fill order was over and the only writer for `pools.priority` outside
  # the pool form, and both are ported to `Category` — where the waterfall now lives
  # (`AllocationCalculator` walks `Category.in_fill_order` over ONE root, so priority is no longer
  # compared inside an account). Nothing in `app/` called either after the Budget page moved, and
  # `Category.apply_fill_order` carries their whole argument forward: the dense renumber, the
  # slot-preserving branch for a holder no rule fills, the four refusals and the lock. `pools
  # .priority` itself survives — `Pool.by_priority` still orders Home's rows — it simply has no
  # drag behind it any more.

  attr_accessor :create_expense_category

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

  # THE WHOLE HISTORY OUTLIVES THE ENVELOPE — spec §7a's "reconsider `dependent: :destroy` on
  # `movements_out` before reallocation ships", answered, plus the half that measuring on a real
  # envelope turned up.
  #
  # TWO KINDS OF HISTORY REACH A POOL AND BOTH HAD TO MOVE. The movements are the ones §7a names;
  # the CATEGORIES are the ones nobody had noticed. `dependent: :nullify` left a destroyed pool's
  # category pointing at nothing, and `PoolCalculator`'s predicate is
  # `COALESCE(entries.pool_id, categories.pool_id) = :id` — so every entry that category ever
  # carried stopped counting toward ANY pool, and `Σ pools` rose by the pool's lifetime spending
  # while the bank had obviously paid it. Measured on the demo's Household Supplies (balance $75 =
  # $120 in by movement − $45 out by entries): the buffer rose by $120 instead of $75 and Σ pools
  # rose by $45. Both halves re-point to the same place for the same reason, so they are one
  # callback and one refusal.
  #
  # Those two associations alone delete every movement with this pool on either end, and in a
  # chain that takes a bystander's money with it: Checking → B $100, B → C $60, and destroying B
  # deletes BOTH rows, so C's inflow evaporates and C silently drops $60. `Σ pools` still equals
  # the bank balance either way — every movement nets to zero in-tree, so conservation is NOT the
  # property that breaks — which is exactly why the defect survived this long. Individual
  # balances are what break.
  #
  # So before anything is deleted, every movement with this pool on an end is RE-POINTED: the
  # destroyed endpoint becomes the pool's own account, which is where the money physically sits
  # anyway. B → C $60 becomes Checking → C $60 and C never moves; Checking → B $100 becomes
  # Checking → Checking, which is not a movement at all, so it is destroyed. Every category
  # pointing at this pool is re-pointed to the same account, so its entries keep counting — in the
  # buffer's lane instead of the envelope's. What is left is the buffer holding EXACTLY what the
  # envelope held, to the penny, and a history that reads as the buffer's own.
  #
  # `prepend: true` IS LOAD-BEARING, AND MORE SO SINCE PLAN 3 TASK 6. `has_many … dependent:`
  # registers its own `before_destroy` when the association is declared, and callbacks run in
  # declaration order — so a plain `before_destroy` here would run AFTER the movements had already
  # been deleted, and it would now run after `restrict_with_error` on #categories had ABORTED the
  # destroy of every envelope that has one. The re-point has to happen before the guard asks.
  #
  # ACCOUNTS ARE EXCLUDED BY TYPE, not by whether they have somewhere to go. An account has no
  # `account` to absorb anything, `restrict_with_error` on #child_pools already refuses one that
  # holds pools, and the movements left on a CHILDLESS account are by construction cross-account
  # transfers — which spec §5 puts out of scope, so `dependent: :destroy` on the two movement
  # associations stays as the backstop for that one case.
  #
  # WHAT DOES NOT STAY IS #categories' `dependent: :nullify` (task 6). It was the ACCOUNT's
  # backstop and it was writing NULL `pool_id`s past a required `belongs_to`; the account's answer
  # is now a refusal, spelled `restrict_with_error` like #child_pools'. The full trace is at the
  # association.
  before_destroy :return_holdings_to_the_account, prepend: true

  # Configure searchable fields
  searchable :name, label: "Name"
  searchable :category, through: :categories, column: :name, label: "Category"

  # ONE ROW OF #timeline, whichever table it came out of. `sign` is +1 for money arriving and -1
  # for money leaving — the same two directions `PoolCalculator#contributions` and `#withdrawals`
  # sum — so the view branches on a number rather than on which class it is holding.
  TimelineRow = Data.define(:date, :name, :detail, :label, :amount, :sign) do
    def inflow? = sign.positive?
  end

  # HOW A MOVEMENT GOT WRITTEN, in the words the rest of the app uses for it. `PoolMovement#kind`
  # is the column; `transfer` is its default and is what every hand-made move and every
  # entry-driven one carries, while a distribution writes the other two.
  MOVEMENT_DETAILS = {
    "transfer" => "moved by hand",
    "allocation" => "this period's distribution",
    "sweep" => "swept back"
  }.freeze

  # THE POOL'S HISTORY, AND POST-CUTOVER IT IS MOSTLY MOVEMENTS (plan 3, task 5).
  #
  # WHAT THIS REPLACES, and why the old shape could not survive. `#contribution_entries` selected
  # entries in a SAVINGS-TYPE category and `#timeline_entries` OR'd it with the expense half. The
  # savings category is gone, so the contributing half selected nothing — every goal's timeline
  # rendered empty while the same goal was visibly receiving money every period, which the pool
  # page's own "Total Contributions" tile printed two inches above the gap. That is the
  # `TODO(plan-3)` this method answers: a contribution IS a `PoolMovement` now, so the timeline
  # reads `movements_in` / `movements_out` — the SAME associations `PoolCalculator#contributions`
  # and `#withdrawals` sum — plus the expense entries of the categories pointing here, which is
  # the other leg of `#withdrawals`. The list and the two tiles above it are the same rows.
  #
  # THE `start_date..` CUTOFF CAME BACK, AND IT IS NOT THIS METHOD'S ANY MORE. The rule this list
  # follows is and has always been "list exactly the rows the two tiles beside it add up"; what
  # changed underneath it is the tiles. It once ran its OWN `start_date..` filter while
  # `PoolCalculator#balance` ignored the date entirely, and that divergence was rightly deleted —
  # a pre-start row counted toward the balance without appearing in the list explaining it. The
  # START-DATE RULE (main-account spec §3) then moved the date INTO the balance: an envelope counts
  # its categories' spending only from its `start_date` on, and earlier spending reads against the
  # user's main account. So the cutoff is in the list again, arriving the only way it may — through
  # `Entry.reaching_pool`, the one expression both the tile and the row now come from — rather than
  # as a second filter this method applies for itself.
  #
  # MOVEMENTS TAKE NO SUCH CUTOFF, and the asymmetry is §3's own: a movement is money put into this
  # pool BY NAME, with no category to date and nothing to relocate, so a pre-start transfer is
  # still in here and still listed. `start_date` also keeps its display job, and
  # `Pool#set_default_start_date` still fills it.
  #
  # `limit` PER SIDE AND AGAIN AFTER THE MERGE. The newest `limit` rows of the union are always
  # inside the union of each side's newest `limit`, so three bounded queries answer what one
  # UNION ALL would — without teaching this model to write SQL across two tables.
  def timeline(limit:)
    (movement_rows(limit) + spending_rows(limit)).sort_by { |row| -row.date.to_i }.first(limit)
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
  # `net_of_sweep:` and `pending:` KEPT THEIR NAMES AND CHANGED THEIR ADDRESS (plan 2d decision 4).
  # They are projections — questions about a ledger nobody has written — and they now belong to
  # PoolProjection, which wraps a plain calculator and owns the arithmetic, the twin and the
  # refusal. This signature does not change, because it is the app's one door onto a pool's figures
  # and every caller of it asks the same questions it always did; `PoolProjection.for` hands back a
  # plain PoolCalculator when neither projection is asked for, so the callers that ask none are on
  # exactly the object they have always had.
  def calculator(as_of: nil, today: Date.current, net_of_sweep: false, pending: PoolProjection::Pending.none,
                 terms: nil)
    PoolProjection.for(
      self, net_of_sweep: net_of_sweep, pending: pending, as_of: as_of, today: today, terms: terms
    )
  end

  # `pending:` threads straight through to the calculator underneath, exactly as it does here:
  # a status is a reading of a balance, so a status of a pool that has not yet received this
  # distribution's money is a status of the wrong balance. It is what lets the distribution
  # screen ask "does this envelope still make it if I fund $200 instead of $500" in the app's
  # own vocabulary rather than inventing a second one.
  # `terms:` threads down the same way and for the same reason, and defaults to nothing here too:
  # a view or a controller asking one pool how it is doing pays five queries either way.
  def status(today: Date.current, pending: PoolProjection::Pending.none, terms: nil)
    PoolStatus.new(self, today: today, pending: pending, terms: terms)
  end

  # What the bank actually says: unallocated cash plus every pool inside it.
  def total
    calculator.current_balance + child_pools.sum { |pool| pool.calculator.current_balance }
  end

  private

  # MONEY IN AND MONEY OUT, from the two associations every balance on every screen is built from.
  # The counterpart pool is the row's name because that is the fact the user needs — where the
  # money came from, or where it went — and it is preloaded so a list of eight rows is two queries
  # rather than ten.
  def movement_rows(limit)
    incoming = movements_in.includes(:from_pool).order(date: :desc).limit(limit).map do |movement|
      timeline_row(movement, movement.from_pool.name, 1)
    end
    outgoing = movements_out.includes(:to_pool).order(date: :desc).limit(limit).map do |movement|
      timeline_row(movement, movement.to_pool.name, -1)
    end

    incoming + outgoing
  end

  def timeline_row(movement, counterpart, sign)
    TimelineRow.new(
      date: movement.date,
      name: counterpart,
      detail: MOVEMENT_DETAILS.fetch(movement.kind),
      label: sign.positive? ? "Moved in" : "Moved out",
      amount: movement.amount,
      sign: sign
    )
  end

  # The other leg of `PoolCalculator#withdrawals`, ASKED WITH THE CALCULATOR'S OWN QUESTION.
  #
  # It used to read `#entries` — `has_many through: :items` — which is the category's-pool arm of
  # `ENTRY_POOL_ID` with the other two missing, and the comment here said so: an entry carrying its
  # own `pool_id` override was counted by the tile and not listed by this, "the one place the list
  # and the tile can differ", left standing because nothing wrote that column. The start-date rule
  # (main-account spec §3) added a second and much louder difference — every entry predating the
  # envelope was listed under it while the tile above had already sent that money to main — so the
  # gap is closed rather than documented: `Entry.reaching_pool` is the calculator's own narrowing,
  # and asking it here makes the list and the tile the same rows by construction. The override arm
  # comes along for free, which is what that old note asked the next person to do.
  def spending_rows(limit)
    Entry.reaching_pool(self).merge(Entry.expenses)
      .includes(item: :category).order(date: :desc).limit(limit).map do |entry|
        TimelineRow.new(
          date: entry.date,
          name: entry.item.name,
          detail: entry.category.name,
          label: "Spent",
          amount: entry.amount,
          sign: -1
        )
      end
  end

  # Every movement this pool is an end of, and every category that points at it, handed to the
  # account that is about to hold its money. Runs inside `destroy`'s own transaction, so a
  # re-point that will not save takes the whole deletion down with it and NOTHING moves — the
  # alternative is a pool half detached from its own history, which no screen could report and no
  # user could undo.
  #
  # Nothing here rescues, for `Category.apply_fill_order`'s reason: `update!` runs the full validation
  # stack, which is deliberate — a deletion must not be the request that sneaks an invalid row
  # past the model — so a row that was ALREADY invalid before the destroy raises RecordInvalid
  # rather than being quietly re-pointed or quietly dropped.
  #
  # EVERY REFUSAL IS DECIDED BEFORE THE FIRST WRITE, and the reason is NOT the one it looks like.
  #
  # Interleaved — movement loop first, refusal after — a pool with one absorbable movement and one
  # unabsorbable category would `update!` the transfer and then `throw(:abort)`, and `destroy`'s own
  # `with_transaction_returning_status` would raise `ActiveRecord::Rollback` and unwind the write.
  # The visible outcome would be identical, and the spec's `reload` assertions would pass either
  # way; see the note on that example, which says so rather than claiming a discrimination it does
  # not make.
  #
  # It is the ordering that stays correct WHEN THE ROLLBACK DOES NOT HAPPEN. `pool.destroy` inside
  # an already-open JOINABLE transaction opens no savepoint, so the `Rollback` is swallowed by the
  # outer block and the outer transaction commits — the same trap AllocationCommitter#call spells
  # out and answers with `requires_new: true`, and the same one Task 7 measured. In that world an
  # interleaved implementation leaves the re-pointed transfer PERSISTED beside a pool that still
  # exists and a refusal the caller was told about: a movement silently re-parented by a delete that
  # did not happen. Deciding first is the version with no such world. No caller wraps `destroy`
  # today; the guarantee costs one extra pass over a handful of rows and does not depend on one.
  #
  # `order(:id)`, matching AllocationCommitter#previous_distribution: each movement write `touch`es
  # both of its pools, so two deletions racing over the same rows must take them in one fixed
  # order or deadlock.
  def return_holdings_to_the_account
    return if pool_type_account?

    targets = adjoining_movements.index_with { |movement| absorbing_account_for(movement) }
    refuse_for_want_of_an_account(:categories) if categories_have_nowhere_to_land?
    refuse_for_want_of_an_account(:movements) if targets.value?(nil)

    # `absorber`, not `account`: the block would otherwise shadow the `account` association for the
    # whole loop, which is the confusion `pool_type_account?`'s prefix exists to prevent one level
    # up — and in the ORPHAN case the shadowed name is not merely confusing but wrong, because
    # `self.account` is nil there and the absorber is the counterparty's.
    targets.each { |movement, absorber| absorb(movement, absorber) }
    hand_categories_to_the_account
    movements_in.reset
    movements_out.reset
  end

  # THE HALF THAT KEEPS Σ POOLS EXACT. A category re-pointed to the user's MAIN account keeps
  # every entry it carries inside the tree — the same COALESCE now resolves them to main instead
  # of to nothing — so Σ is unmoved even though the destroyed pool's balance no longer lands in
  # one place.
  #
  # THE DESTINATION IS `user.default_account`, NOT `account` (main-account spec §6, fix round 2 —
  # B2). It read `account` — this pool's OWN containing account — until a category on an envelope
  # living in a NON-main account made that re-point illegal the instant `Category
  # #pool_must_be_reachable` shipped: `update!` raised `ActiveRecord::RecordInvalid`,
  # `PoolsController#destroy` has no rescue for it, and deleting an ordinary envelope 500'd. §6 is
  # explicit that a category may point only at main or an envelope, so main is the only legal
  # destination left, and it is also the right one on its own terms: §3's start-date rule already
  # sends an envelope's PRE-START history to main, so a destroyed envelope's post-start history
  # joining it there is the same rule extended past the pool's own death rather than a new one.
  #
  # A SPLIT RESULT ON A NON-MAIN ENVELOPE, and it is not a defect: the movements above this method
  # (absorbed by `#absorb`) still land in THIS pool's own account, because a movement is a
  # transfer between two of the user's pools and has nothing to do with where a category's
  # SPENDING is allowed to be counted. Destroying an envelope that lived in "Ally" and carried
  # both a funding movement and a category therefore leaves Ally holding the movement and main
  # holding the category's history — two accounts, not one — and Σ across both is still exactly
  # the pool's balance. Only a main-account envelope keeps both halves in the same place, because
  # there `account` and `user.default_account` are the same pool.
  #
  # `update!` per record and not `update_all`, for the reason `Category.apply_fill_order` gives and one
  # specific to this table: `income_must_land_in_an_account` polices where income may land and the
  # required `belongs_to :pool` polices that it lands somewhere, and a deletion must not be the
  # request that routes around either. (`destroy_budget_if_pool_linked` used to fire here too and
  # destroy the category's cap; the cap is deleted in plan 3, task 3.) It costs one UPDATE per
  # category, and a pool has a handful.
  #
  # Guarded on `user.default_account`, which cannot be nil here — the refusal above has already
  # returned for a categories-holding pool whose user has no main account. Stated so the guard
  # reads as the invariant it is rather than as a nil-check somebody could delete.
  #
  # `reset` afterwards, AND IT IS NOW LOAD-BEARING — the previous note here said, correctly at the
  # time, that it "does not fire": `dependent: :nullify` reached `update_all` over a re-queried
  # scope (`Category.where(pool_id: <this pool>)`), which after the re-point matched nothing, so
  # the loaded target was never consulted. Plan 3 task 6 replaced that option with
  # `restrict_with_error`, which asks `#empty?` — and `#empty?` TRUSTS A LOADED TARGET over the
  # database. Without this line the `each` above leaves three re-pointed categories sitting in the
  # association's target, the guard counts them, and an envelope that has just handed everything
  # to its account refuses to be destroyed.
  #
  # Mutation-tested at the swap, both before and after: deleting this line failed NOTHING under
  # `nullify` and fails THREE examples in `spec/models/pool_destroy_spec.rb` under
  # `restrict_with_error` (the buffer figure, the re-point and the allocation collapse — the whole
  # envelope-with-history block). The comment it replaces was true when written; the line it
  # describes was kept "for symmetry", and symmetry is what caught this.
  def hand_categories_to_the_account
    return if user.default_account.blank?

    categories.each { |category| category.update!(pool: user.default_account) }
    categories.reset
  end

  # `PoolMovement` directly rather than through the two associations, because the associations
  # are the very things about to delete these rows: a relation loaded here would be the target
  # `dependent: :destroy` walks, and it must be re-read after the re-point rather than reused.
  # (Hence the two `reset`s above — a caller that touched `pool.movements_in` before calling
  # `destroy` would otherwise hand the dependency a cached list of rows that have already moved.)
  def adjoining_movements
    PoolMovement.where(from_pool_id: id).or(PoolMovement.where(to_pool_id: id)).order(:id)
  end

  # Where this movement's money is going once this pool is gone: this pool's own account, and
  # for an account-less pool the COUNTERPARTY's account instead.
  #
  # The fallback WAS not a courtesy and is now unreachable, for the reason `REFUSALS` gives: a
  # non-account pool with no account is refused by the model and by a CHECK constraint since plan
  # 3 task 6. It is kept as that constant's other half. The paragraph below is why it was written,
  # and it is left standing because it is also why it is safe to keep: savings pools were
  # account-less until Plan 3's backfill, and a movement of an orphan's is by
  # definition a same-user transfer with a real pool on the other end — so the counterparty's
  # buffer is the one place in the tree the money can land while staying inside the account it
  # is already sitting in. A counterparty that is ITSELF an account stands in as its own, which
  # is what makes an orphan → Checking transfer collapse rather than re-point.
  #
  # NIL is an answer, not a failure to compute one: two account-less pools transferring between
  # themselves name no account anywhere, and there is nowhere for the row to go.
  def absorbing_account_for(movement)
    account || buffer_of(other_end_of(movement))
  end

  def buffer_of(pool) = pool.pool_type_account? ? pool : pool.account

  # A movement whose OTHER end is already the absorbing account collapses to account → account
  # once this one is re-pointed, and a movement from an account to itself is not a movement: it
  # is the buffer's own money sitting still. Destroyed rather than saved, because
  # #pools_must_differ would refuse it — and rightly. This is the ordinary shape of a
  # distribution's own rows: an allocation runs account → envelope and a sweep runs envelope →
  # account, so destroying the envelope collapses both.
  #
  # `kind` is deliberately untouched on the rows that survive. A re-pointed transfer is still
  # the transfer the user made; `PoolMovement.distributed` selects allocations and sweeps, and
  # those are exactly the rows that collapse, so a re-pointed row cannot be picked up by a later
  # distribution's replacement.
  # `absorber` rather than `account`, for the reason its caller's block parameter carries the same
  # name: `account` here would read as this pool's own, and for an orphan it is the counterparty's.
  def absorb(movement, absorber)
    if other_end_of(movement) == absorber
      movement.destroy!
    elsif movement.from_pool_id == id
      movement.update!(from_pool: absorber)
    else
      movement.update!(to_pool: absorber)
    end
  end

  # THE END THAT IS NOT THIS POOL. The two ends always differ (#pools_must_differ and a check
  # constraint), so exactly one of them is this pool and the other is always found.
  def other_end_of(movement) = movement.from_pool_id == id ? movement.to_pool : movement.from_pool

  # BOTH WAYS A CATEGORY CAN HAVE NOWHERE TO LAND, decided here rather than inside
  # `#hand_categories_to_the_account` for the reason `#return_holdings_to_the_account`'s header
  # gives — every refusal before the first write. `account.blank?` is the orphan case `REFUSALS`
  # already explains (retained pending the follow-up that note names); `user.default_account.
  # blank?` is new with main-account spec §6, which made the re-point destination the user's
  # MAIN account rather than this pool's own — a user who somehow has none named would otherwise
  # hit `update!` raising `ActiveRecord::RecordInvalid` mid-destroy, the same production 500 the
  # destination change exists to close.
  def categories_have_nowhere_to_land?
    (account.blank? || user.default_account.blank?) && categories.exists?
  end

  def refuse_for_want_of_an_account(reason)
    errors.add(:base, REFUSALS.fetch(reason))
    throw(:abort)
  end

  # EVERY POOL IS EITHER AN ACCOUNT OR LIVES IN ONE (spec §3.2; §7a's Plan-3 item, done here).
  # The `TODO(plan-3)` this replaces exempted SAVINGS pools, because until the cutover backfilled
  # them an account-less goal was the ordinary shape a user had — the table was `savings_pools`
  # and nothing in it named an account. `CutoverToEnvelopeBudgeting#house_the_pools` houses every
  # one and its verifier refuses to commit while a single non-account pool has no account, so the
  # exemption now protects nothing and hides the state Home has been asking users to fix in three
  # places since Plan 2a.
  #
  # The database says the same thing one level down (`pools_account_matches_pool_type`, a CHECK
  # over `(pool_type = 0) = (account_id IS NULL)`), which is what makes it true of rows written
  # past this model — `update_all`, a fixture, a console. What the CHECK cannot say is the rest of
  # this method: that the named parent is an ACCOUNT belonging to the SAME user needs a subquery,
  # and a CHECK constraint may not contain one.
  def account_matches_pool_type
    return errors.add(:account, "cannot be set on an account") if pool_type_account? && account_id.present?
    return if pool_type_account?

    return errors.add(:account, "must be set for envelopes and goals") if account.blank?

    account_is_this_users_account
  end

  # The half a CHECK constraint cannot hold, split out so the whole rule stays inside one AbcSize:
  # both questions are about the pool NAMED as the parent rather than about this row's own columns.
  def account_is_this_users_account
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

  def set_default_start_date
    self.start_date ||= Date.current
  end

  # ONE CHECKBOX, NOT TWO (plan 3, task 5). `create_savings_category` minted a SAVINGS category,
  # which is not a type any more — a pool is filled by movements, and the category a pool needs is
  # the one that spends OUT of it.
  def create_auto_categories
    return unless boolean_cast(create_expense_category)

    categories.create!(
      user: user,
      name: unique_category_name("#{name} Expense"),
      category_type: :expense
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
