# frozen_string_literal: true

# Everything the Home screen renders — BOTH LEDGERS OVER ONE TOTAL (two-ledger spec §2). Read-only:
# it builds no movements, writes no allocations and saves nothing; the fix buttons below are LINKS
# to the reallocation screen, which owns the write.
#
#   THE PHYSICAL BAND  — the accounts, each showing what the bank says. `AccountLedger#balance_of`,
#                        and main's balance IS the pot. Accounts no longer contain anything: the
#                        `pools_for(account)` nesting, the orphan band and the whole apparatus that
#                        went with them are deleted (Task 6).
#   THE PURPOSE BAND   — AVAILABLE and the holder categories that hold the rest. `CategoryLedger`,
#                        `Category.in_fill_order`, and ONE waterfall over ONE root.
#
# WHAT THE COLLAPSE FROM PER-ACCOUNT TO ONE ROOT ACTUALLY DELETED, said here because five readers
# on this class existed only to carry it: `#account_pots`, `#sweeps_by_account`, `#fill_waterfall`'s
# per-account pot map, `#cutoff`'s `accounts.one?` gate and `#projected_buffer`'s "cash in an account
# with nothing left to fund" reading. Allocating money is an act of intention rather than of location
# (§2), so there is no account for money to be stranded in and no second reason the standing band's
# figures fail to subtract. #shortfall and `total_required - available` now agree wherever available
# is non-negative, and #projected_buffer is positive only on a covered period.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2 and
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4
class HomePresenter
  # WHAT ONE PROBLEM ROW OFFERS TO DO ABOUT ITSELF (spec §4.2): the amount to move, the source that
  # can genuinely cover it, and what the move would cost the source.
  #
  # `candidate` is a ReallocationPresenter::Candidate, not a shape of our own — the same object, from
  # the same class, that the screen this button opens will render half a second later. "What would
  # this move cost" has one answer, and Home prints it through the same `AllocationsHelper` sentence
  # `/allocations/new` prints. Two readers answering one question has produced a defect in every task
  # on this plan.
  #
  # nil `candidate` is the no-fix case and is REACHABLE — see #fix_candidates_for. The view says so
  # in words rather than rendering a dead button.
  Fix = Data.define(:category, :amount, :candidate, :covered) do
    # THE CANDIDATE ITSELF, not a record inside it: a source may be AVAILABLE, which is not a
    # category at all (ReallocationPresenter::ROOT). Both answer #id and #name, which is the whole
    # reason the root is a null object rather than a `nil`.
    def source = candidate

    # The next distribution funds this category's whole ask, so there is nothing for a move to do.
    # See HomePresenter#covered_by_waterfall?.
    def covered? = covered

    # WHETHER MOVING MONEY IN WOULD CHANGE ANYTHING, and it is a real branch rather than a guard.
    # `amount` is HoldingStatus#funding_gap, which is zero for an overdue bill whose category already
    # holds the money — the demo's Renters Insurance. That category needs paying, not funding, and
    # the view says so instead of offering a button that would double-fund it.
    def needs_money? = amount.positive?

    # PLAIN DIGITS FOR THE QUERY STRING. `number_to_rounded` scales to two decimals and is asked for
    # `delimiter: ""`, so a four-figure amount cannot reach `?amount=` as "1,500.00" — which the
    # browser would read as one dollar fifty. `DigitsHelper.digits` is the one spelling of "money a
    # browser can parse" on this branch; four copies of it is four chances to leave the delimiter in.
    def amount_param = DigitsHelper.digits(amount)
  end

  # ONE CATEGORY AS A ROW, AND IT IS `BudgetPagePresenter::Group`'S SHAPE ON PURPOSE.
  #
  # The two screens print the same sentence about the same category, and twice now they have printed
  # it differently: the Budget page's group passed `period_closed:` and not
  # `changed_after_distributing:`, and Home's own two bands passed one suffix each. Both defects were
  # possible for one reason — `pool_status_label` takes the suffixes as OPTIONAL keywords, so every
  # caller is free to thread one and forget the other, and a forgotten one is silent.
  #
  # This is the fix, and it is structural rather than vigilant: `shared/_holding_status` threads both
  # suffixes off ONE object, and that object is this Data — so a caller does not decide which
  # suffixes to pass, it decides which OBJECT to pass, and an object missing an answer raises
  # NoMethodError at render rather than dropping a clause.
  #
  # `orphan` IS GONE (Task 6) and so is `#needs_attention?`'s OR with it. A category belongs to no
  # account and needs none — allocating money moves nothing physical (§2) — so the state "nothing can
  # fund this" has no shape left to describe, and the status alone decides both the colour and the
  # auto-expand.
  Row = Data.define(:category, :status, :period_closed, :changed_after_distributing) do
    def period_closed? = period_closed
    def changed_after_distributing? = changed_after_distributing
    delegate :needs_attention?, to: :status

    # THE CLAUSE THIS SCREEN ADDS AFTER THE STATE, and Home's is a date. Of the three quiet states —
    # `on track`, `saving` and `left to spend` — only the first has one to add: the other two have no
    # anchored rule to take a date from, so #due_on is nil there anyway. A row needing attention has
    # already said its date inside the label.
    def due_marker? = !status.needs_attention? && status.due_on.present?

    # Home does NOT print `· holds $X`, which is the Budget page's clause. Both screens print one
    # clause after the state and they are different clauses, deliberately: a Home row shows no rules
    # and no balance elsewhere, so a date is the thing it is missing, while a Budget card lists every
    # rule underneath and is missing only the money. Said here rather than in the partial so the
    # partial asks the row instead of asking which screen it is on.
    def balance_clause? = false
  end

  attr_reader :user, :today

  # `rejected_movement:` IS ONBOARDING STEP 2'S OWN 422 (main-account spec §5), threaded through
  # rather than read off an ivar the view would have to know about. AccountFundingsController's
  # failure branch hands back the unsaved, invalid PoolMovement it tried to save, and #funding_
  # movement_for below is how the ONE account it was for gets it back — every other account's
  # card renders a fresh, blank one. Optional and nil everywhere else Home is built, which is
  # every other caller of this presenter.
  #
  # A `PoolMovement` AND NOT AN `Allocation`, which is not a leftover: account funding is a move on
  # the PHYSICAL ledger (main → the account it is really in), and that lane is untouched by this plan
  # until Task 8 renames its table. Nothing on the purpose side has a form on this screen.
  def initialize(user:, today: Date.current, rejected_movement: nil)
    @user = user
    @today = today
    @rejected_movement = rejected_movement
  end

  # ── THE PHYSICAL LEDGER ────────────────────────────────────────────────────────────────────────

  def accounts
    @accounts ||= user.pools.accounts.order(:name).to_a
  end

  # WHAT THE BANK SAYS ABOUT ONE ACCOUNT — `AccountLedger#balance_of`, and for MAIN that figure is
  # the pot (§2: income − expenses − Σ moves out + Σ moves in).
  #
  # It was `#current_buffer_for`, and the rename is the model rather than a tidy-up. A "buffer" was
  # an account's cash net of the envelopes housed inside it; nothing is housed inside an account any
  # more, so the account's balance IS everything it holds and there is no unallocated remainder to
  # name. The word ALSO moved: the distribution screen calls AVAILABLE the buffer (§7.1 — the money
  # no category has claimed), so leaving it here would have put one word over two different
  # quantities on one screen, which is the exact defect #projected_buffer vs #current_buffer_for was
  # split to prevent.
  #
  # ONE LEDGER FOR EVERY ACCOUNT ON THE SCREEN, so the accounts band, the overdraft lines and the two
  # onboarding gates all read one snapshot.
  delegate :balance_of, to: :account_ledger

  # Accounts that have gone below zero, and the loudest fact on the screen.
  #
  # THEY ARE NOT PROBLEM ROWS ANY MORE (Task 6), and that is a correction rather than a loss. An
  # overdrawn account is a PHYSICAL fact — money already spent out of a bank account — and the fix
  # button beside a problem row proposes an ALLOCATION, which moves nothing physical (§2). Offering
  # one here would be a real mistake proposed to fix a problem it cannot touch, which is the same
  # ruling that keeps a fix off an overdue bill whose category already holds the money. The standing
  # band names the account and the figure in red, and the accounts band prints the negative balance;
  # what goes away is the button, not the debt.
  def overdrawn_accounts
    accounts.select { |account| balance_of(account).negative? }
  end

  # The debt as a positive figure, for the sentence that states it. `-balance`, exactly as
  # HoldingStatus spells :overdrawn's own amount.
  def overdraft_for(account) = -balance_of(account)

  # ONBOARDING STEP 2'S ONE GATE (main-account spec §5): not main, and holding no money yet. ONE
  # predicate, asked by the view (which account gets the card — home/_account.html.erb) and by
  # AccountFundingsController (which write is legal), so the two cannot drift into two different
  # answers about the same account.
  #
  # `AccountLedger#balance_of` WHERE THIS READ `Pool#total` (Task 6). That reader was "unallocated
  # cash PLUS every envelope housed inside it", and it existed because an account whose envelopes
  # held every dollar it had read as "never funded" — the card came back under a fully funded account
  # asking the user to match their bank statement a second time. Nothing is housed inside an account
  # now, so the family total and the balance are the same figure and only one of them still has a
  # reader. `Pool#total` is envelope-era and dies in Task 8.
  #
  # MED-1'S PROTECTION SURVIVES UNCHANGED, which is what the money test is for: a fresh account is
  # zero however many categories the user owns, because a category is not inside it. Deliberately NOT
  # "has no categories" in any spelling — money is the only signal.
  #
  # `user.default_account.present?` FIRST (HIGH-1, a 500 fixed): `users.default_account_id` nullifies
  # when main is deleted, and the card used to read `main_account.name` unconditionally — a user with
  # no main account 500'd on Home with no door back in. No main account means no card anywhere, full
  # stop, not merely "no card on the pool that used to be main": every account is equally un-fundable
  # with nothing to fund it FROM.
  def awaiting_funding?(account)
    user.default_account.present? && account != user.default_account && balance_of(account).zero?
  end

  # ONBOARDING STEP 3'S OWN GATE (main-account spec §5): the account under review must BE the user's
  # main account — not merely funded, this correction only ever applies to the one account that isn't
  # funded by a movement — and the one-time latch, the "Opening Balance" category's own existence,
  # must still be open. Asked here (which account gets the card — home/_account.html.erb) and
  # LITERALLY BY `OpeningBalancesController#create`, which builds its own presenter and calls this
  # same method rather than re-spelling either half of it, so the card's render gate and the write's
  # legality gate cannot drift into two different answers.
  #
  # `user.default_account.present?` FIRST, for the same HIGH-1 reason #awaiting_funding? checks it
  # first. It also makes `awaiting_opening_balance?(nil)` — reachable if a crafted POST names no
  # account — false rather than a NoMethodError, because `nil.present?` short-circuits the `&&`
  # before `account == user.default_account` is ever asked.
  def awaiting_opening_balance?(account)
    user.default_account.present? && account == user.default_account && !opening_balance_recorded?
  end

  # THE FUND-ACCOUNT CARD'S FORM OBJECT (onboarding step 2). The rejected movement if THIS is the
  # account it was refused for — so its typed amount and its errors survive the re-render, the same
  # courtesy BankAccountsController's own 422 branch pays the add-account card — and a fresh unsaved
  # one otherwise, so every other card's `simple_form_for` still has a record to ask for a (blank)
  # value rather than a bare symbol with nothing behind it.
  def funding_movement_for(account)
    return @rejected_movement if @rejected_movement&.to_pool_id == account.id

    AccountMovement.new(to_pool: account)
  end

  # ── THE PURPOSE LEDGER ─────────────────────────────────────────────────────────────────────────

  # THE CATEGORIES THAT HOLD MONEY, in the order a distribution reaches them. `Category.in_fill_order`
  # rather than a scope of this screen's own: it is holders (`expense? && funded_since.present?`)
  # ordered `[priority, name]`, which is exactly the set and exactly the order AllocationCalculator
  # fills — so the band, the waterfall and the action the button opens cannot fall into different
  # orders or over different sets. Priority alone is not a total order; `name` is unique per user, so
  # the pair is.
  #
  # `:budgets` eager-loaded because every row asks for them three times over — #dated_rules_for,
  # the status's anchored rules, and DistributionClock#changed_after_distributing?.
  def categories
    @categories ||= user.categories.in_fill_order.includes(:budgets).to_a
  end

  # MONEY WITH NO JOB YET, PLUS WHAT THE NEXT DISTRIBUTION SWEEPS BACK — `AllocationCalculator
  # #available` to the character, and that identity is the point rather than a coincidence.
  #
  # THE SWEEP IS NOT DOUBLE-COUNTING: swept money is inside the user's total but not inside
  # `CategoryLedger#available`, because funding the category was an allocation out. It is sitting in a
  # category and the sweep is what moves it back to the root.
  #
  # NOT CLAMPED AT ZERO, which is the one place this reader CHANGED with the collapse to one root.
  # The pool era clamped each account's pot before summing, because an overdrawn account cancelling a
  # healthy one's surplus gives a figure that is true about net worth and false about what can be
  # allocated. There is no sibling to cancel against now — one root — so a negative available is a
  # fact the screen must state rather than a figure to round up to nothing, exactly as
  # AllocationCalculator leaves it. The two screens no longer diverge; the divergence that used to be
  # pinned in spec/system/home/fixes_spec.rb is gone with the accounts it was about.
  #
  # IT IS NOW THE PROPOSAL'S OWN FIGURE RATHER THAN AN EXPRESSION THAT MATCHED IT (Task 7, the T6
  # review's adopted recommendation). This read `ledger.available + total_swept`, which is
  # character-for-character `AllocationCalculator#available` — two spellings of one figure, kept in
  # step by three cross-pins in the specs. Delegated, they cannot drift at all.
  delegate :available, to: :proposal

  # What every rule asks for this period — an honest answer to "what do I owe". Post-sweep, exactly
  # as the distribution screen computes it, and now off the SAME ROWS: a category the fill rejects
  # for asking nothing contributes nothing to a sum over the rows, which is what the per-category
  # loop this replaced computed the long way round. The `0.to_d` seed is the type guarantee for the
  # user with no rows at all.
  def total_required = waterfall.sum(0.to_d, &:needed)

  # Fills top-down by priority, exactly as a distribution would, so the user sees who gets paid first
  # and where the money ran out.
  #
  # ONE POT, NOT ONE PER ACCOUNT (§2). The pool era filled each account's own buffer because money
  # could not cross an account boundary; an allocation crosses nothing, so a single `remaining` is
  # the model rather than a simplification of it — and it is `AllocationCalculator#fill`'s own shape.
  #
  # Memoised because #shortfall, #covered?, #projected_buffer and #covered_by_waterfall? all derive
  # from these rows, so a Home render asks for them several times over.
  # ROWS ARE `AllocationCalculator::Row` NOW, not hashes this class fills itself (Task 7). They
  # answer #category, #needed, #funded and #short.
  #
  # `Struct#[]` ANSWERS THE FIRST THREE BY NAME AND RAISES ON THE FOURTH, which is worth writing
  # down because it decided which lines had to change: `category`, `needed` and `funded` are
  # MEMBERS, so `home/_attention.html.erb`'s `row[:funded]` renders unchanged; `short` is a METHOD
  # (`needed - funded`, so a fourth member would be a second place for one number to be wrong), and
  # `row[:short]` raises `NameError: no member 'short' in struct`. Every reader of it here is
  # `row.short` — measured, not reasoned about: #cutoff's block took the root route down until it
  # was.
  def waterfall = proposal.rows

  # WHERE THE MONEY RAN OUT, or nil when there is no such moment. The rule itself is Waterfall's —
  # the distribution screen draws the same line off the same reader — and only the GATE is Home's.
  #
  # THE `accounts.one?` HALF OF THAT GATE IS DELETED (Task 6). It existed because each account
  # drained its own pot, so with several there was no single moment the money ran out. There is one
  # root, so there is one moment, and a user with three accounts sees the line exactly as a user with
  # one does.
  #
  # `covered?` survives: the waterfall renders on a covered period too, and there the index finds
  # nothing, falls back to `rows.length` and draws "ran out here · $0.00 unfunded" under the last row
  # of a screen where nothing ran out at all.
  def cutoff
    return nil if covered?

    Waterfall.cutoff(waterfall) { |row| [row.funded, row.short] }
  end

  # Derived from the waterfall rows, NOT from `total_required - available`.
  #
  # The two agree on every ordinary screen now — one root, no orphans — and they still part company
  # on a NEGATIVE available, where the subtraction reports more than any distribution could be short
  # by. Only the rows can say WHICH category is starved, which is the question a distribution acts
  # on, so the rows stay the source.
  #
  # No `max` clamp is needed: every row's `short` is `needed - funded` where `funded` is clamped to
  # at most `needed`, so no row can contribute a negative.
  def shortfall = waterfall.sum(0.to_d, &:short)

  def covered? = shortfall.zero?

  # Money that has no job even after this period's funding — `available` less every row's funding.
  #
  # WITH ONE ROOT IT IS POSITIVE ONLY ON A COVERED PERIOD, which is a real simplification rather than
  # an accident: it used to double as "cash in an account whose own pools are already funded, which
  # cannot close a gap somewhere else", and that reading died with the accounts. A short period
  # drains the root to zero, so the standing band's short branch has no buffer clause left to print.
  #
  # ** THE CONVERSE IS FALSE, AND SAYING IT WAS THE DEFECT (fix round 1 — MED-1). ** A covered period
  # does NOT imply this is positive. `#covered?` is `shortfall.zero?`, which a user with no holder
  # categories satisfies trivially — nothing asks, so nothing is short — while their unbudgeted
  # spending has drained the root below zero. Measured: $100 of spending with no rules rendered
  # "You're covered this period" over "-$100.00 is still unclaimed after this period", a deficit
  # called unclaimed money on the root route.
  #
  # THE EXACT LAW IS `projected_buffer.negative? ⟺ available.negative?`, and it falls out of the
  # fill: `funded` is `remaining.clamp(0.to_d, needed)`, so with a non-negative root every row funds
  # at most what is left and `Σ funded ≤ available`, while with a negative root every row funds
  # exactly zero and this IS `available`. `home/_standing.html.erb` gates on that one condition
  # rather than on this figure's own sign, so the band has one question to ask on either branch.
  def projected_buffer = proposal.leftover

  # Sorted for the same reason #waterfall is, and by the same key: this is a rendered list, and the
  # order the user ranked their categories in is the order "what do I deal with" wants. #categories
  # is already `[priority, name]`, so the select preserves it.
  def attention_categories
    categories.select { |category| status_for(category).needs_attention? }
  end

  # THE ROW OBJECT `shared/_holding_status` IS GIVEN, built here rather than in the partial for the
  # reason #status_for and #period_closed? are: every member is dated against THIS presenter's
  # `today`, and a view assembling its own would be free to build one of them against `Date.current`
  # and disagree with the rest of the screen silently.
  #
  # Both suffixes are read HERE, together, for every row — which is the point. They used to be two
  # keyword arguments a partial could pass separately, and Home's two bands did exactly that.
  def row_for(category)
    Row.new(
      category: category,
      status: status_for(category),
      period_closed: period_closed?(category),
      changed_after_distributing: changed_after_distributing?(category)
    )
  end

  # Views MUST use this rather than calling `category.status` directly. HoldingStatus defaults to
  # Date.current, so a bare call in a partial would compute against a different day than this
  # presenter whenever `today` is injected — and disagree silently.
  def status_for(category)
    @statuses ||= {}
    @statuses[category.id] ||= category.status(today: today, terms: ledger.terms_for(category))
  end

  # Whether this category's money belongs to a period that has already ended — what the row marks as
  # ` · last period` and what the next distribution will sweep back.
  #
  # Here rather than in the partial for the same reason as #status_for, and routed through
  # #calculator_for so it reuses the calculator Home has already built for this category.
  def period_closed?(category) = calculator_for(category).period_closed?

  # SPEC §8'S ONE ROUGH EDGE — `behind $50.00 — you changed a rule here after distributing`, the
  # clause that tells a user whose category went red because they edited a rule apart from one whose
  # money genuinely went missing.
  #
  # `DistributionClock` OWNS THE WHOLE ANSWER, including the wording's justification and the
  # period-bounded query behind it. It moved out of this class when the Budget page had to print the
  # same clause, and Task 6 moved this caller onto its CATEGORY arm: one root means one distribution
  # per period and one moment it happened at, so the clock takes a user and no account list at all.
  #
  # `delegate` TO A PRIVATE METHOD, and both halves are deliberate. Rails emits an implicit-receiver
  # call, so a private target is reachable; and the laziness this screen needs lives inside
  # #distribution_clock's own memo, so the clock's one query runs only when a row actually asks.
  delegate :changed_after_distributing?, to: :distribution_clock

  # The dated rules behind a category, earliest due first, each paired with the due date its row
  # prints. What an expanded row shows: a category needing attention owes the user the rules that put
  # it there.
  #
  # Here rather than in the partial for the same reason as #status_for, one level down:
  # `budget.calculator` defaults to Date.current, so a view building its own calculators would date
  # these rules against a different day than every other figure on the screen.
  #
  # Anchorless rules are excluded because they have no date to print; a row whose rules are all
  # anchorless renders its own explanation instead (see _holding_row). The sort key is
  # BudgetCalculator#due_order, the same one HoldingStatus#anchored_budgets and the fill order itself
  # use — `category.budgets` carries no ORDER BY, so without it two rules sharing a due date could
  # swap places between page loads. Memoised because BudgetCalculator#due_date re-runs its
  # paid_since_anchor SUM on every call, which is also why the date this has already computed is
  # handed to #due_order rather than left for it to ask again.
  def dated_rules_for(category)
    (@dated_rules ||= {})[category.id] ||= category.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, calculator_for_budget(budget).due_date] }
      .sort_by { |budget, due_on| calculator_for_budget(budget).due_order(due_on) }
  end

  # ── THE STANDING BAND'S TWO REMAINING READERS ──────────────────────────────────────────────────

  # WHICH PERIOD THE STANDING BAND IS TALKING ABOUT, or nil for a user who has declared none.
  #
  # `User#period_containing`, the one method that owns this arithmetic — the same window
  # `DistributionPresenter#period` and `EntryImpactPresenter#period_ends_on` both read off, never
  # re-derived here. GATED ON THE DECLARATION rather than taken on trust: `period_containing` falls
  # back to the calendar month for an undeclared user, which is the right fallback for a normaliser
  # and a lie on this band, since "Aug 1 – Aug 31" would state a boundary the user never set.
  def period_range
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today)
  end

  # DOES THE BUDGET FIT THE INCOME — a question about the shape of the rules, not about this
  # afternoon's cash.
  #
  # `Budget.steady_need`, not `total_required`, which is THIS period's ask — catch-up on anything
  # behind, zero on anything already funded — and the two diverge in both directions on the same
  # budget. A period spent catching up on a slipped bill reported "your budget doesn't fit your
  # income" at someone whose rules fit it comfortably, and the period right after a distribution
  # reported nothing at all on a budget that does not fit. The second is the dangerous one: the whole
  # point of the check is that reallocation cannot fix a budget that does not fit.
  #
  # BOTH HALVES OF THE DECLARATION, income AND cadence — the same gate `BudgetPagePresenter#declared?`
  # applies, because it is the same question. Income with a blank cadence is a reachable state, and in
  # it `Budget.steady_need` falls back to treating the period as a calendar month. That fallback is
  # right for a per-rule normaliser and useless as a verdict: "$1,668 a period" at a user who has not
  # said how long a period is states a figure with no unit, and this band delivers the verdict WITHOUT
  # the figures that would justify it. `/budget` already refuses to print those figures; Home refusing
  # to print the verdict from them is the same refusal.
  #
  # Memoised, and the `false` case has to be memoised too — `||=` would recompute the whole sum on
  # every call for exactly the users who answer false.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    @structurally_underwater =
      user.typical_income.present? &&
      user.period_cadence.present? &&
      Budget.steady_need(user, today: today) > user.typical_income.to_d
  end

  # ── THE FIX A PROBLEM ROW OFFERS ───────────────────────────────────────────────────────────────

  # WHAT MOVING MONEY IN WOULD ACTUALLY CLOSE — HoldingStatus#funding_gap, not #amount.
  #
  # The two coincide on :overdrawn, :behind and :wont_make_it, and those are the only attention
  # states whose ROW prints a figure at all (`overdrawn $80.00`, `behind $385.00`; the other prints a
  # date), so the button and the label beside it still name one number.
  #
  # They diverge on :overdue, and taking #amount there was a measured defect: the demo's Renters
  # Insurance holds every penny of a $180 premium that has simply not been paid, and Home offered
  # "Take $180.00 from Available" — a real mistake proposed to fix an imaginary problem, which would
  # have left the category holding $360 against a $180 bill. #funding_gap returns zero there, and the
  # band says what the bill actually needs instead. See _attention.html.erb.
  #
  # `.round(2)` so the THREE places this figure lands cannot disagree: the button's label (rounded by
  # number_to_currency), the link's `amount=` (rounded by Fix#amount_param) and the damage preview
  # (computed from whatever is passed to ReallocationPresenter). Display-identical either way; the
  # point is that the link and its own preview describe one move.
  def fix_amount_for(category) = status_for(category).funding_gap.round(2)

  # THE PARTIES WITH ENOUGH FREE MONEY, IN THE ORDER THE REALLOCATION SCREEN OFFERS THEM.
  #
  # AVAILABLE IS ALWAYS ONE OF THEM AND IS ALWAYS FIRST — `ReallocationPresenter#sources`' own order,
  # for its own reason: idle money costs nothing to move, while a category's money is money the user
  # decided to protect. Richest-first proposed exactly the opposite on the demo — a $950 house down
  # payment offered four times over while $330 of unallocated money sat unoffered.
  #
  # THERE IS NO SAME-ACCOUNT TEST. `PoolMovement#crosses_accounts?` decided which pools could reach
  # each other; an allocation moves nothing physical (§2), so every one of the user's holder
  # categories is reachable from every other and the whole filter is gone.
  #
  # `free_amount` — holding less what EVERY rule holds — and not the balance, which is the threshold
  # a USER-INITIATED move is gated on (ReallocationPresenter::Candidate#affordable?). Two thresholds
  # for two different acts, deliberately: there the app STATES the damage rather than forbidding the
  # move, here the app is PROPOSING, so it must not propose robbing a category that is counting on the
  # money. AVAILABLE is in the third case by construction — it holds money for no rule, so its free
  # amount is its whole holding.
  #
  # A category whose own status needs attention is excluded outright: proposing to rob a category that
  # is itself behind is not a fix.
  def fix_candidates_for(category)
    (@fix_candidates ||= {})[category.id] ||= compute_fix_candidates(category)
  end

  # The one fix a problem row renders. nil `candidate` is the no-source case.
  #
  # `fetch` with a block rather than `||=`, because nil is a real answer here and `||=` would rebuild
  # it on every hit.
  def fix_for(category)
    @fixes ||= {}
    @fixes.fetch(category.id) { @fixes[category.id] = build_fix(category) }
  end

  private

  # ONE PHYSICAL LEDGER FOR THE SCREEN. Lazy, like everything else here: Home writes nothing, so
  # there is no write for the snapshot to fall the wrong side of, and the laziness is only so a
  # presenter built and never rendered costs nothing.
  def account_ledger = @account_ledger ||= AccountLedger.new(user)

  # ONE PURPOSE LEDGER FOR THE SCREEN, over exactly the categories this screen asks about, plus
  # `user:` so `#available` is answerable for a user whose holder set is EMPTY — which is every user
  # on their first day, and exactly the user Home renders for first. Read off the categories alone,
  # CategoryLedger raises `NoSingleOwner` rather than answering.
  def ledger = @ledger ||= CategoryLedger.new(categories, user: user)

  # THE LATCH ITSELF, memoised: #awaiting_opening_balance? is asked once per account this screen
  # renders, and every account but main gets a `false` from the first half of that predicate before
  # this one is ever reached.
  #
  # `Category.opening_balance`, NOT a hand-rolled `exists?(name: …)`: that scope is CASE-INSENSITIVE,
  # matching `Category`'s own uniqueness validation, so a user who already has a category spelled
  # "opening balance" reads as latched here exactly as it would refuse a second `create!` — one rule,
  # asked the one place it lives.
  #
  # `defined?` rather than `||=`: the open latch (no such category yet) is `false`, the common case
  # for as long as onboarding is unfinished, and `||=` would re-run the EXISTS on every hit.
  def opening_balance_recorded?
    return @opening_balance_recorded if defined?(@opening_balance_recorded)

    @opening_balance_recorded = user.categories.opening_balance.exists?
  end

  # ONE CLOCK FOR THE SCREEN, on its category arm — no account list, because there is one root and
  # one distribution per period to compare against.
  def distribution_clock
    @distribution_clock ||= DistributionClock.new(user: user, today: today)
  end

  def compute_fix_candidates(category)
    amount = fix_amount_for(category)
    return [] unless amount.positive?

    fundable_by(category).select { |party| free_amount_for(party) >= amount }
  end

  # AVAILABLE, THEN THE HOLDERS IN FILL ORDER — `ReallocationPresenter#sources`' order, assembled
  # from the list Home already holds rather than re-queried.
  def parties = @parties ||= [ReallocationPresenter::ROOT, *categories]

  def fundable_by(category)
    parties.reject do |party|
      next true if party == category

      !root?(party) && status_for(party).needs_attention?
    end
  end

  def root?(party) = party.is_a?(ReallocationPresenter::Root)

  # AVAILABLE'S FREE MONEY IS `CategoryLedger#available`, NOT THIS SCREEN'S `#available`, and the
  # difference is the sweep. The headline is post-sweep because it describes the distribution this
  # screen is offering; a hand move happens NOW, out of money that is actually unclaimed today, which
  # is what the reallocation screen would then show and refuse against (`Allocation#source_must_hold_
  # it` reads the same figure). Offering a fix out of money that is still sitting in another category
  # would propose a move the write path rejects.
  def free_amount_for(party)
    return ledger.available if root?(party)

    (@free_amounts ||= {})[party.id] ||= calculator_for(party).free_amount
  end

  # ONE ReallocationPresenter FOR ONE ROW, and #source_for rather than #sources: the list reader would
  # build a Candidate — with its damage, four calculators deep — for every holder category the user
  # has, on a screen that renders one button.
  def build_fix(category)
    amount = fix_amount_for(category)
    return Fix.new(category: category, amount: amount, candidate: nil, covered: true) if covered_by_waterfall?(category)

    source = fix_candidates_for(category).first
    Fix.new(
      category: category,
      amount: amount,
      candidate: source && damage_reader(category, source, amount).source_for(source),
      covered: false
    )
  end

  # WHETHER THE NEXT DISTRIBUTION ALREADY SOLVES THIS, so the band does not talk the user into a move
  # they do not need to make. Ruling 4 said do not offer money to a bill that already has it; this is
  # the same principle one step out — do not offer money to a bill that is ABOUT to have it. The move
  # is not free: the source loses money it was holding for its own rule.
  #
  # READ OFF #waterfall, WHICH IS THE PROPOSAL THIS SCREEN IS ALREADY RENDERING, and deliberately not
  # a fresh AllocationCalculator. The waterfall band sits a few inches below this row on the same
  # screen; a second reader here could say "the next distribution funds this in full" above a row
  # reading `$0.00 of $300.00` — a screen contradicting itself in two adjacent bands.
  #
  # NO ROW MEANS NOT COVERED, which is the safe direction: a category asking for nothing is rejected
  # from the rows, and that category is already handled one branch earlier by
  # HoldingStatus#funding_gap.
  def covered_by_waterfall?(category)
    row = waterfall_rows_by_category[category.id]

    row.present? && row.short.zero?
  end

  def waterfall_rows_by_category
    @waterfall_rows_by_category ||= waterfall.index_by { |row| row.category.id }
  end

  # THE SCREEN'S OWN LEDGER GOES WITH IT, and that is the whole of what `ledger:` is for. One of these
  # is built per problem row (see #build_fix), and each would otherwise open a CategoryLedger of its
  # own over the same holder categories, at the same moment, with no `as_of` on either.
  #
  # SHARING IS SAFE HERE BECAUSE HOME WRITES NOTHING. A ledger is a snapshot memoised at its first
  # read, so handing one across a write would hand out figures from before it; this presenter renders
  # a GET and the fix buttons are links.
  #
  # The two sets are identical by construction: both are `Category.in_fill_order` over the same user.
  # It would not cost accuracy if one were not — #terms_for hands back nil for a category the ledger
  # does not know and the calculator then runs its own aggregates — but #holding_of would raise, so
  # "identical" is worth stating rather than relying on.
  def damage_reader(category, source, amount)
    ReallocationPresenter.new(
      user: user, to_category: category, from_category: source, amount: amount, today: today, ledger: ledger
    )
  end

  # THE PROPOSAL THIS SCREEN RENDERS, AND IT IS THE OBJECT THE DISTRIBUTE BUTTON ACTS ON.
  #
  # HOME USED TO KEEP A HAND-COPIED WATERFALL — `#fill_waterfall`, plus `#required_for` and
  # `#ask_calculator_for` to feed it, plus `#total_swept` and an `available` expression, all of them
  # transcriptions of `AllocationCalculator`. They agreed, and they agreed by being watched: five
  # cross-screen pins in `spec/presenters/home_presenter_spec.rb` and `spec/system/home/fixes_spec.rb`
  # exist for no other reason than to catch the day they stopped. Consuming the class removes the
  # copy rather than the check — those pins now compare an object with itself and stay green, which
  # is what "structurally cannot drift" looks like from a spec's side.
  #
  # THE COST IS ONE EXTRA `CategoryLedger`, AND IT IS THE HONEST PRICE. This presenter keeps its own
  # ledger for the statuses, the free-money reads and the `ReallocationPresenter`s it builds; the
  # proposal builds a second over the same categories at the same moment, because `#share_ledger` is
  # `protected` — only another AllocationCalculator may hand one over, deliberately, since only
  # another instance can honestly promise it was constructed after the last write. Widening that
  # surface to save four grouped queries would trade the guarantee for the saving, and Home writes
  # nothing, so the two ledgers cannot disagree about anything. The alternative — keeping the copy —
  # costs the same queries AND the drift.
  #
  # NO `overrides:`: Home renders the proposal as it stands. The overrides are the distribution
  # screen's, where there are boxes to type them into.
  def proposal = @proposal ||= AllocationCalculator.new(user: user, today: today)

  # THE PLAIN CALCULATOR — what a category holds right now. #period_closed? and #free_amount_for
  # both ask it, once per rendered category, and each calculator is a set of aggregate queries plus
  # a per-rule sort, so the memo is what stops the screen building two for one category.
  #
  # THE AGGREGATES ARE ONE LEDGER'S SHARE OF FOUR. The memo only ever stopped this screen building
  # the same calculator twice; the ledger is what stops each category paying four aggregates of its
  # own.
  def calculator_for(category)
    (@calculators ||= {})[category.id] ||= category.holding_calculator(today: today, terms: ledger.terms_for(category))
  end

  # Keyed by the record, not by id: an unsaved rule has no id, and `nil` as a cache key would hand
  # every such rule the first one's calculator.
  def calculator_for_budget(budget)
    (@budget_calculators ||= {})[budget] ||= budget.calculator(today: today)
  end
end
