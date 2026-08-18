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
  #     re-points every category to the pool's own account (`#hand_categories_to_the_account`) or
  #     refuses the destroy outright. By the time this dependency is consulted the scope is empty —
  #     which the old comment on `#hand_categories_to_the_account` already recorded, measured:
  #     dropping its `reset` failed nothing, because nullify never had a row to find.
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
  # not over the one it leaves. `CutoverToEnvelopeBudgeting#preflight!` is what names that shape.
  #
  # SO THEY STAY FOR THE HONEST REASON: they are retained pending the follow-up that deletes the
  # whole orphan apparatus, not as a guard against anything. That follow-up is larger than this
  # constant and its blast radius is written down so it can be scoped rather than rediscovered:
  # these two refusals and `#absorbing_account_for`'s counterparty fallback here;
  # `HomePresenter#orphan_pools`, `#orphan_required`, `#orphan_pools_owed`, `Row#orphan` and the
  # exclusion in `#fill_waterfall` that keeps orphans out of the waterfall; the `home/_orphans`
  # partial and the `orphan_pools_owed` term in `home/_attention`; `BudgetPagePresenter`'s
  # `#orphan_rules` and `#orphan_reason`; and `ReallocationPresenter`'s "No account" group.
  REFUSALS = {
    categories: "can't be deleted while categories point at it and it sits in no account — its " \
                "spending would stop counting toward any pool. Assign it to an account first.",
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

  # THE POOLS AN ACCOUNT ACTUALLY FILLS, and therefore the ones a fill order is over: an envelope
  # with no funding rule asks for nothing, AllocationCalculator#fill drops its zero-ask row before
  # the waterfall reaches it, and the Budget page — which groups rules under the pool they fill —
  # has no card to drag for it. One reader for that set, because `.apply_fill_order` refuses a
  # list that is not exactly it and BudgetPagePresenter renders exactly it.
  #
  # `distinct` MAKES THIS ORDER BADLY, and the failure is a 500 rather than a wrong order —
  # `PG::InvalidColumnReference: for SELECT DISTINCT, ORDER BY expressions must appear in select
  # list`. The review note said this fires on `.in_fill_order.by_priority`; MEASURED ON THE DEMO IT
  # DOES NOT, and the correction is mine. `distinct` emits `SELECT DISTINCT pools.*`, which already
  # contains `priority` and `name`, so that pair composes fine and answers 14 pools.
  #
  # What actually raises is anything that NARROWS the select list out from under the ORDER BY, or
  # orders by the joined table. All four measured:
  #
  #   Pool.in_fill_order.by_priority.ids          # raises — `ids` selects only pools.id
  #   Pool.in_fill_order.by_priority.pluck(:id)   # raises — same reason
  #   Pool.in_fill_order.select(:id).by_priority  # raises — same reason
  #   Pool.in_fill_order.order("budgets.amount")  # raises — budgets.amount is not selected
  #
  # `.apply_fill_order` sits one keystroke from the first of those: it asks
  # `account.child_pools.in_fill_order.ids`, which is safe only because it does NOT order. Order in
  # Ruby, as BudgetPagePresenter does with its `[priority, name]` sort.
  scope :in_fill_order, -> { joins(:budgets).distinct }

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
  #
  # TWO REORDERS AT ONCE ARE LAST-WRITE-WINS, AND THAT IS A DECISION RATHER THAN A LEAVING.
  # `account.lock!` IS THE FIRST STATEMENT INSIDE THE TRANSACTION, exactly as it is in
  # AllocationCommitter#call and for a related reason: without it two tabs reordering the same
  # account issue their UPDATEs in their own submitted orders, take the same pool rows in
  # DIFFERENT orders, and Postgres breaks the cycle by killing one with a deadlock — a 500 on a
  # button click. Serialised behind the account row, the second reorder simply lands on top of
  # the first, whole. It cannot land HALF on top: the submitted list must be the account's entire
  # `in_fill_order` set, so every ordered pool is rewritten by whichever transaction commits last
  # and no blend of two orders exists. The staleness check moved INSIDE the lock for the same
  # reason — a rule deleted between the check and the write would otherwise slip past a guard
  # that had already passed.
  #
  # Nothing here rescues. `update!` runs the full validation stack on every row, which is
  # deliberate — this is the only writer for `priority` and a reorder must not be the request
  # that sneaks an invalid row past the model — so a row that was ALREADY invalid before the
  # reorder (a name emptied by a migration, a start_date backfilled to NULL) raises
  # RecordInvalid, the transaction rolls back, and BudgetPageController#reorder turns it into the
  # same 422 as every other refusal with the offending row named. A rescue here would have to
  # invent a second failure vocabulary beside `nil`.
  def self.apply_fill_order(user:, pool_ids:)
    ids = Array(pool_ids).map(&:to_s)
    pools = fill_order_pools(user, ids)
    return if pools.nil?

    account = fill_order_account(user, pools.values)
    return if account.nil?

    transaction do
      account.lock!
      next unless account.child_pools.in_fill_order.ids.map(&:to_s).sort == ids.sort

      write_fill_order(user, account, ids, pools)
      account
    end
  end

  # The submitted pools dropped into the slots the submitted pools already hold, everything else
  # left where it stands, and the whole account renumbered 0,1,2… off the result.
  #
  # `user.pools.where(account_id:)` rather than `account.child_pools`, so the write set is scoped
  # by the same ownership the ids were: `child_pools` walks a foreign key, and that the rows
  # behind it belong to this user is today only true because `account_matches_pool_type` says so
  # at save time. A validation is an input rule; this is the write, and it does its own scoping.
  def self.write_fill_order(user, account, ids, pools)
    queue = ids.dup
    user.pools.where(account_id: account.id).by_priority
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
  # THE `start_date..` CUTOFF DID NOT SURVIVE, and that was the second half of the TODO's
  # question. It was a deliberate divergence from `PoolCalculator#balance` (which is
  # start-date-agnostic) on the argument that a goal's story begins when the goal did — so a
  # pre-start row counted toward the balance without appearing in the list explaining it. With the
  # list now built out of exactly the rows the two tiles beside it add up, a cutoff on one and not
  # the other is the two-readers defect this branch has found in every task. `start_date` keeps its
  # other job: it is a display attribute, and `Pool#set_default_start_date` still fills it.
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

  # The other leg of `PoolCalculator#withdrawals`: what was spent out of this pool through the
  # categories that point at it. `#entries` is `has_many through: :items`, so this is the
  # category's-pool half of `ENTRY_POOL_ID` — an entry carrying its own `pool_id` override is
  # counted by the calculator and is not listed here, which is the one place the list and the tile
  # can differ. Nothing in this app writes that column (see `#override_entries`), and the day
  # something does, this is the method that has to learn about it.
  def spending_rows(limit)
    entries.merge(Entry.expenses).includes(:item, item: :category).order(date: :desc).limit(limit).map do |entry|
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
  # Nothing here rescues, for `.apply_fill_order`'s reason: `update!` runs the full validation
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
    refuse_for_want_of_an_account(:categories) if account.blank? && categories.exists?
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

  # THE HALF THAT KEEPS Σ POOLS EXACT. A category re-pointed to the account keeps every entry it
  # carries inside the tree — the same COALESCE now resolves them to the buffer instead of to
  # nothing — so the buffer ends up holding the destroyed pool's balance to the penny rather than
  # only its movement half.
  #
  # `update!` per record and not `update_all`, for the reason `.apply_fill_order` gives and one
  # specific to this table: `income_must_land_in_an_account` polices where income may land and the
  # required `belongs_to :pool` polices that it lands somewhere, and a deletion must not be the
  # request that routes around either. (`destroy_budget_if_pool_linked` used to fire here too and
  # destroy the category's cap; the cap is deleted in plan 3, task 3.) It costs one UPDATE per
  # category, and a pool has a handful.
  #
  # Guarded on `account`, which cannot be nil here — the refusal above has already returned for the
  # account-less pool that has any category at all. Stated so the guard reads as the invariant it
  # is rather than as a nil-check somebody could delete.
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
    return if account.blank?

    categories.each { |category| category.update!(pool: account) }
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
