# frozen_string_literal: true

# Everything the Home screen renders. Read-only: it builds no movements and saves nothing —
# the fix buttons below are LINKS to the reallocation screen, which owns the write.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4
class HomePresenter
  # WHAT ONE PROBLEM ROW OFFERS TO DO ABOUT ITSELF (spec §4.2): the amount to move, the source
  # that can genuinely cover it, and what the move would cost the source.
  #
  # `candidate` is a ReallocationPresenter::Candidate, not a shape of our own, and that is
  # amendment A honoured rather than decorated: "what would this move cost" already has one
  # answer on this branch (`Candidate#damage`, two real recomputations of PoolCalculator#required),
  # and Home renders it through the same PoolMovementsHelper sentence the reallocation screen
  # prints. Two readers answering one question has produced a defect in every task on this plan.
  #
  # nil `candidate` is the no-fix case and is REACHABLE — see #fix_candidates_for. The view says
  # so in words rather than rendering a dead button.
  Fix = Data.define(:pool, :amount, :candidate, :covered) do
    def source = candidate&.pool

    # The next distribution funds this pool's whole ask, so there is nothing for a move to do.
    # See HomePresenter#covered_by_waterfall?.
    def covered? = covered

    # WHETHER MOVING MONEY IN WOULD CHANGE ANYTHING, and it is a real branch rather than a guard.
    # `amount` is PoolStatus#funding_gap, which is zero for an overdue bill whose envelope already
    # holds the money — the demo's Renters Insurance. That pool needs paying, not funding, and the
    # view says so instead of offering a button that would double-fund it.
    def needs_money? = amount.positive?

    # PLAIN DIGITS FOR THE QUERY STRING, for ReallocationPresenter#amount_value's reason one screen
    # later: `BigDecimal("300").to_s` is "0.3e3", which reaches the link as `amount=0.3e3`. It is
    # read back correctly (`to_d` parses it) but it is the URL the user sees and copies.
    #
    # THAT REASON HAS SINCE EXPIRED AND THE METHOD HAS NOT (measured while Task 9 was copying the
    # same reader): on bigdecimal 4.0.1, which is what this branch resolves,
    # `BigDecimal("300").to_s` is "300.0" and `BigDecimal("692.31").to_s` is "692.31". Kept,
    # because the SECOND thing it does is still live and always was — `number_to_rounded` scales
    # to two decimals, and it is asked for `delimiter: ""` so a four-figure amount cannot reach a
    # query string as "1,500.00". Recorded rather than deleted so nobody re-derives the old claim
    # from the code and finds it false.
    #
    # `DigitsHelper.digits` since 2d Task 4: this was a byte-identical copy of the sacrifice view's
    # spelling, which the impact card made a third consumer of. Four copies of "money a browser can
    # parse" is four chances to leave the delimiter in.
    def amount_param = DigitsHelper.digits(amount)
  end

  # ONE POOL AS A ROW, AND IT IS `BudgetPagePresenter::Group`'S SHAPE ON PURPOSE (2d task 6).
  #
  # The two screens print the same sentence about the same envelope, and twice now they have
  # printed it differently: `_pool_group` passed `period_closed:` and not
  # `changed_after_distributing:`, and Home's own two bands passed one suffix each. Both defects
  # were possible for one reason — `pool_status_label` takes the suffixes as OPTIONAL keywords, so
  # every caller is free to thread one and forget the other, and a forgotten one is silent.
  #
  # This is the fix, and it is structural rather than vigilant: `shared/_pool_status` threads both
  # suffixes off ONE object, and that object is this Data — so a caller does not decide which
  # suffixes to pass, it decides which OBJECT to pass, and an object missing an answer raises
  # NoMethodError at render rather than dropping a clause. The Budget page's Group answers the same
  # four questions; a third caller (the category page's pool card) answers them too.
  #
  # `orphan` is Home's alone and rides here rather than in the partial because it changes what the
  # row IS, not how it is drawn: a pool no account holds is in trouble whatever its status says —
  # nothing can fund it — so it opens with the rest of the trouble and takes the red. Hence
  # #needs_attention? is the status's OR this, and the partial can ask one question.
  Row = Data.define(:pool, :status, :period_closed, :changed_after_distributing, :orphan) do
    def period_closed? = period_closed
    def changed_after_distributing? = changed_after_distributing
    def orphan? = orphan
    def needs_attention? = status.needs_attention? || orphan

    # THE CLAUSE THIS SCREEN ADDS AFTER THE STATE, and Home's is a date. Of the three quiet
    # states — `on track`, `saving` and `left to spend` — only the first has one to add: the other
    # two have no anchored rule to take a date from, so #due_on is nil there anyway.
    #
    # ** THE STATUS, NOT THE ROW, AND THE DIFFERENCE IS AN ORPHAN. ** This gate reads
    # `status.needs_attention?` rather than this Data's own #needs_attention?, which is the OR with
    # `orphan`. Written the other way — as it briefly was — an orphan pool whose OWN status is quiet
    # and which has an anchored rule lost its date: `$50.00 · on track · Oct 17` became
    # `$50.00 · on track`. The tempting justification ("a row needing attention has said its date
    # inside the label") is false exactly there, because `pool_status_label` knows nothing about
    # orphanhood — it renders the QUIET label, and this clause was the only date on the line.
    #
    # So the two questions are genuinely different and both belong: orphanhood decides the COLOUR
    # and the auto-expand (nothing can fund this pool, whatever its balance says), and the status
    # alone decides whether the label has already spent the date.
    def due_marker? = !status.needs_attention? && status.due_on.present?

    # Home does NOT print `· holds $X`, which is the Budget page's clause. Both screens print one
    # clause after the state and they are different clauses, deliberately: a Home row shows no
    # rules and no balance elsewhere, so a date is the thing it is missing, while a Budget card
    # lists every rule underneath and is missing only the money. Said here rather than in the
    # partial so the partial asks the row instead of asking which screen it is on.
    def balance_clause? = false
  end

  attr_reader :user, :today

  # `rejected_movement:` IS ONBOARDING STEP 2'S OWN 422 (main-account spec §5), threaded through
  # rather than read off an ivar the view would have to know about. AccountFundingsController's
  # failure branch hands back the unsaved, invalid PoolMovement it tried to save, and #funding_
  # movement_for below is how the ONE account it was for gets it back — every other account's
  # card renders a fresh, blank one. Optional and nil everywhere else Home is built, which is
  # every other caller of this presenter.
  def initialize(user:, today: Date.current, rejected_movement: nil)
    @user = user
    @today = today
    @rejected_movement = rejected_movement
  end

  def accounts
    @accounts ||= user.pools.accounts.order(:name).to_a
  end

  # ONBOARDING STEP 2'S ONE GATE (main-account spec §5, fix round 2 — MED-1/2/3 in one ruling):
  # not main, and holding no money yet. ONE predicate, asked by the view (which account gets the
  # card — home/_account.html.erb) and by AccountFundingsController (which write is legal), so
  # the two cannot drift into two different answers about the same account the way they had —
  # the controller used to spell "already funded" as `child_pools.exists? || balance != 0`,
  # disagreeing with the view's own `pools.empty?`, and an account with an envelope created
  # before it was ever funded could never reach the card (pools.empty? was false) while a crafted
  # POST against it 422'd on a balance that was, in fact, zero. Money is the only signal an
  # envelope's mere existence says nothing about whether this account has been given its real
  # balance.
  #
  # `user.default_account.present?` FIRST (HIGH-1, a 500 fixed): `users.default_account_id`
  # nullifies when main is deleted, and the card used to read `main_account.name`
  # unconditionally — a user with no main account 500'd on Home with no door back in. No main
  # account means no card anywhere, full stop, not merely "no card on the pool that used to be
  # main" — every account is equally un-fundable with nothing to fund it FROM.
  def awaiting_funding?(account)
    user.default_account.present? && account != user.default_account && current_buffer_for(account).zero?
  end

  # ONBOARDING STEP 3'S OWN GATE (main-account spec §5): the account under review must BE the
  # user's main account — not merely funded, this correction only ever applies to the one account
  # that isn't funded by a movement — and the one-time latch, the "Opening Balance" category's own
  # existence, must still be open. Asked here (which account gets the card —
  # home/_account.html.erb) and LITERALLY BY `OpeningBalancesController#create`, which builds its
  # own presenter and calls this same method rather than re-spelling either half of it — the same
  # one-predicate discipline `AccountFundingsController#fund` already carries for
  # #awaiting_funding? (see its own comment), so the card's render gate and the write's legality
  # gate cannot drift into two different answers about whether the correction has already run.
  #
  # `user.default_account.present?` FIRST, for the same HIGH-1 reason #awaiting_funding? checks it
  # first: a user with no main account has no card to show, full stop, not merely no card on the
  # account that isn't there. It also makes `awaiting_opening_balance?(nil)` — reachable if a
  # crafted POST names no account — false rather than a NoMethodError one line into the balance
  # math, because `nil.present?` short-circuits the `&&` before `account == user.default_account`
  # is ever asked.
  def awaiting_opening_balance?(account)
    user.default_account.present? && account == user.default_account && !opening_balance_recorded?
  end

  # THE FUND-ACCOUNT CARD'S FORM OBJECT (onboarding step 2). The rejected movement if THIS is
  # the account it was refused for — so its typed amount and its errors survive the re-render,
  # the same courtesy BankAccountsController's own 422 branch pays the add-account card — and a
  # fresh unsaved one otherwise, so every other card's `simple_form_for` still has a record to
  # ask for a (blank) value rather than a bare symbol with nothing behind it.
  def funding_movement_for(account)
    return @rejected_movement if @rejected_movement&.to_pool_id == account.id

    PoolMovement.new(to_pool: account)
  end

  def pools_for(account)
    by_priority(all_pools.select { |pool| pool.account_id == account.id })
  end

  # Pools belonging to no account. #pools_for filters on account_id, so a view built as
  # "for each account, render pools_for" would render these nowhere at all.
  #
  # THE SHAPE THIS READS FOR NO LONGER EXISTS. The note here said "savings pools stay
  # account-less until Plan 3's backfill, so today this is the ordinary shape for a savings goal";
  # the backfill has run. `CutoverToEnvelopeBudgeting#house_the_pools` houses every non-account
  # pool and refuses to commit while one is left, `Pool#account_matches_pool_type` refuses a new
  # one, and `CHECK ((pool_type = 0) = (account_id IS NULL))` refuses it past the model — so this
  # method answers `[]` for every user and every band built on it renders for nobody. It is kept
  # only until the follow-up that deletes the apparatus whole; `Pool::REFUSALS` carries that
  # follow-up's blast radius, and this method is on it.
  #
  # These no longer appear in #waterfall or #shortfall (see #fill_waterfall). An orphan is
  # a SETUP problem, not a funding one — the money may be sitting in Checking already and
  # simply have nowhere to go, and the fix is assigning the pool, not finding more cash —
  # so Home surfaces them in the attention list, by name, as their own kind of problem.
  # They stay in #total_required: the user does genuinely owe that money.
  def orphan_pools
    by_priority(all_pools.select { |pool| pool.account_id.nil? })
  end

  # ONE account's buffer as it stands right now: the cash sitting in it that no envelope
  # has taken yet. Money moved into a pool has left the account, so the account's balance
  # IS its buffer.
  #
  # Named for the moment it describes, because #projected_buffer is the same concept at a
  # different one — after this period's funding, across every account. They used to be
  # `buffer` and `buffer_for`: two different quantities four characters apart, and neither
  # derivable from the other. Σ current_buffer_for is NOT #projected_buffer — the
  # difference is what the waterfall will spend, and an overdrawn account is clamped out of
  # #available before the sum — so a reader who guessed got a plausible wrong number.
  #
  # `.to_d` was this method's own guard while PoolCalculator#balance could hand back the
  # Integer literal 0 — five `sum(:amount)` calls, all empty on an account with no entries.
  # #balance now coerces at its own source, so this is belt to its braces rather than the
  # only thing standing between a buffer bar and Integer division on exactly the accounts
  # that are emptiest. Kept because this is the public money reader the views divide by.
  def current_buffer_for(account) = calculator_for(account).balance.to_d

  # Unclaimed cash across every account once the next distribution has swept — an honest answer
  # to "what do I have", asked about the moment the button on this screen would create.
  #
  # THE SWEEP IS THE HALF THAT ARRIVED IN TASK 8, and it moves with #required (see
  # #ask_calculator_for). Home used to read the live balance while the distribution screen read
  # the post-sweep one, so a closed envelope said `needs $315` here and `needs $400` there: a
  # screen disagreeing with the action it is offering. Both halves move or neither does.
  #
  # #shortfall IS NOT INVARIANT ACROSS THIS CHANGE, and the tempting claim that it must be is
  # false — do not restore it. Required and available rise by the same amount only while a closed
  # envelope's leftover is no larger than what its rule re-asks for. #sweepable_amount takes the
  # WHOLE leftover; the post-sweep ask rises only to the rule's own figure. An envelope holding
  # $150 against a $100 rate rule therefore adds $150 to available and $100 to required, and the
  # gap correctly CLOSES by the $50 of surplus that was unspendable while it sat in the envelope.
  # Measured on the demo seeds: Pet Care's $50 sweep against a $25 rise took the shortfall from
  # $713.43 to $688.43.
  #
  # WHAT DOES HOLD, EXACTLY, AND THE ONE ACCOUNT WHERE IT DOES NOT. The SHORTFALL agrees with
  # AllocationCalculator per account in every shape, and the specs pin it. This figure agrees with
  # `AllocationCalculator#available` only while that account's available is NON-NEGATIVE, and the
  # difference is deliberate on both sides: #account_pots clamps at zero because Home AGGREGATES
  # across accounts, where an unclamped negative would let one overdrawn account cancel another's
  # surplus, while the distribution screen is per-account and has no sibling to cancel against, so
  # it states the overdraft. Measured on the demo seeds, per account:
  #
  #   Ally Savings 820.00 = 820.00 · Checking 455.00 = 455.00 · Health Savings 400.00 = 400.00
  #   Side Gig Checking — Home 0.00, the distribution screen -300.00
  #
  # It is a divergence with a stated reason rather than a drift, so it is PINNED rather than left
  # latent — see the overdrawn example in spec/system/home/fixes_spec.rb, which asserts both
  # figures and the shortfall's continued agreement on the same fixture.
  #
  # Note this is NOT `total_required - shortfall`: see #shortfall for why the gap is
  # derived from the rows instead, and why the two can legitimately disagree.
  def available
    @available ||= account_pots.values.sum(0.to_d)
  end

  # What every rule asks for this period — an honest answer to "what do I owe",
  # regardless of which account the money would have to come from. Post-sweep, exactly as the
  # distribution screen computes it; see #ask_calculator_for.
  def total_required
    @total_required ||= all_pools.sum(0.to_d) { |pool| required_for(pool) }
  end

  # Derived from the waterfall rows, NOT from `total_required - available`.
  #
  # The two are not the same number once a user has more than one account, and only this
  # one is actionable. `total_required - available` asks "is there enough money anywhere",
  # which reads as covered while a bill sits in an account with nothing in it: Checking
  # empty with rent due, Ally holding $1,000 and no envelopes, and the screen says you are
  # fine above a row funded at zero. Summing the rows asks "will every envelope actually be
  # filled", which is the only question a distribution can act on.
  #
  # An account-less pool is NOT in this figure — the rows it sums exclude them. A gap means
  # money you need and do not have, and an orphan's money may be sitting in Checking right
  # now with nowhere to go; counting it here made a setup problem masquerade as a shortfall.
  # See #orphan_pools.
  #
  # A reader CAN subtract the standing band's two figures, and the answer is not this one:
  #
  #   (total_required - available) - shortfall = orphan_required - projected_buffer
  #
  # Two causes, either of which can be alone: cash sitting in an account whose own pools are
  # already funded (#projected_buffer), and money owed by a pool no account can fund (#orphan_required).
  # A single-account user with every pool assigned has neither, and the figures reconcile
  # exactly; a single account plus one savings goal — the ordinary shape until Plan 3's
  # backfill — has the second. The standing band owes an explanation whenever either is
  # non-zero, and gating on #projected_buffer alone suppresses it on exactly the second case.
  #
  # No `max` clamp is needed: every row's `short` is `needed - funded` where `funded` is
  # clamped to at most `needed`, so no row can contribute a negative.
  def shortfall = waterfall.sum(0.to_d) { |row| row[:short] }

  def covered? = shortfall.zero?

  # Accounts that have gone below zero, loudest state first on the attention list.
  #
  # Nothing else on this screen can say this. #account_pots clamps a negative balance to
  # zero, so an overdraft never reaches #available; and #shortfall is summed from the
  # waterfall rows, so it is not a funding gap either — a user $500 down with a $300 rule
  # correctly reads `short $300`, not `short $800`. Both choices are right, and together
  # they mean real debt renders NOWHERE unless a band asks for it by name. #current_buffer_for
  # still reports the -$500, so the data was never lost, only unspoken for.
  #
  # These are exactly the accounts whose PoolStatus is :overdrawn — an account holds no
  # anchored rules, so :overdue, :wont_make_it and :behind cannot fire on one — which lets
  # Home render them with the same row vocabulary as any other problem.
  def overdrawn_accounts
    accounts.select { |account| current_buffer_for(account).negative? }
  end

  # Cash still sitting in accounts once the waterfall has funded everything it can reach:
  # `available` minus every row's funding, so `Σ max(0, pot_a - required_a)`. One number,
  # two readings, which is why it is one method:
  #
  #   covered → this is the buffer, money that simply stays put.
  #   short   → this is money that CANNOT close the gap, because the gap is in another
  #             account. It is ONE of the two reasons the standing band's figures do not
  #             subtract to the headline — see #shortfall for the algebra and
  #             #orphan_required for the other — and it is exactly zero whenever a
  #             single-account user is short, because the pot drains until it is empty.
  #
  # Never `available - total_required`: an account-less pool counts toward #total_required
  # but can never be funded, so that subtraction reports a NEGATIVE buffer on a covered
  # period — "-$400.00 stays in your buffer" — for a user whose accounts are in order.
  def projected_buffer = available - waterfall.sum(0.to_d) { |row| row[:funded] }

  # What the account-less pools ask for this period: the part of #total_required that no
  # waterfall row can ever fund, and the second reason the standing band's figures do not
  # subtract to its own headline. Derived from the rows rather than by re-summing the
  # orphans, so it cannot drift from whatever #fill_waterfall decided to leave out.
  #
  # Money does not fix this one — assigning the pool to an account does — which is why the
  # band says so in those words instead of folding it into the gap.
  def orphan_required = total_required - waterfall.sum(0.to_d) { |row| row[:needed] }

  # The orphans #orphan_required is actually made of, which is NOT every orphan.
  #
  # The standing band prints that figure and a count of these in one sentence, so the two have
  # to describe the same set or the reader divides one by the other and gets an answer about
  # pools that are asking for nothing: "$200.00 … belongs to 2 pools with no account" reads as
  # roughly $100 each when one of the two owns the whole $200. Same defect as gating the clause
  # on `orphan_pools.any?` — a figure and its explanation drifting apart — one clause later.
  #
  # Every orphan is still a problem and still named, by the attention band and by the pools
  # band. It is only the arithmetic this sentence claims that narrows to these.
  def orphan_pools_owed = orphan_pools.select { |pool| required_for(pool).positive? }

  # THE ROW OBJECT `shared/_pool_status` IS GIVEN, built here rather than in the partial for the
  # reason #status_for and #period_closed? are: every member is dated against THIS presenter's
  # `today`, and a view assembling its own would be free to build one of them against
  # `Date.current` and disagree with the rest of the screen silently.
  #
  # Both suffixes are read HERE, together, for every row — which is the point. They used to be two
  # keyword arguments a partial could pass separately, and Home's two bands did exactly that.
  def row_for(pool, orphan: false)
    Row.new(
      pool: pool,
      status: status_for(pool),
      period_closed: period_closed?(pool),
      changed_after_distributing: changed_after_distributing?(pool),
      orphan: orphan
    )
  end

  # Views MUST use this rather than calling pool.status directly. PoolStatus defaults
  # to Date.current, so a bare call in a partial would compute against a different day
  # than this presenter whenever `today` is injected — and disagree silently.
  def status_for(pool)
    @statuses ||= {}
    @statuses[pool.id] ||= pool.status(today: today, terms: ledger.terms_for(pool))
  end

  # Whether this pool's money belongs to a period that has already ended — what the row marks
  # as ` · last period` and what the next distribution will sweep back.
  #
  # Here rather than in the partial for the same reason as #status_for: PoolCalculator defaults
  # to Date.current, so a view building its own would answer against a different day than every
  # other figure on the screen whenever `today` is injected, and disagree silently. Routed
  # through #calculator_for so it reuses the calculator Home has already built for this pool.
  def period_closed?(pool) = calculator_for(pool).period_closed?

  # SPEC §8'S ONE ROUGH EDGE — `behind $50.00 — you changed a rule here after distributing`, the
  # clause that tells a user whose envelope went red because they edited a rule apart from one
  # whose money genuinely went missing.
  #
  # `DistributionClock` OWNS THE WHOLE ANSWER, including the wording's justification and the
  # period-bounded movement query behind it. It moved out of this class when the Budget page had to
  # print the same clause: the screen where rules are EDITED was the one screen omitting it, and
  # the alternative to one reader was that query copied into a second presenter, free to disagree
  # about which distribution is "this period's".
  #
  # `delegate` TO A PRIVATE METHOD, and both halves are deliberate. Rails emits an implicit-receiver
  # call, so a private target is reachable; and the laziness this screen needs lives inside
  # #distribution_clock's own memo rather than here, so the clock is still built off #accounts —
  # already loaded — and only when a row actually asks.
  delegate :changed_after_distributing?, to: :distribution_clock

  # The dated rules behind a pool, earliest due first, each paired with the due date its
  # row prints. What an expanded row shows: a pool needing attention owes the user the
  # rules that put it there.
  #
  # Here rather than in the partial for the same reason as #status_for, one level down:
  # `budget.calculator` defaults to Date.current, so a view building its own calculators
  # would date these rules against a different day than every other figure on the screen
  # whenever `today` is injected — and disagree silently.
  #
  # Anchorless rules are excluded because they have no date to print; a row whose rules are
  # all anchorless renders its own explanation instead (see _pool_row). The sort key is
  # BudgetCalculator#due_order, the same one PoolStatus#anchored_budgets and the fill order
  # itself use — `pool.budgets` carries no ORDER BY, so without it two rules sharing a due date
  # could swap places between page loads. Memoised because BudgetCalculator#due_date re-runs its
  # paid_since_anchor SUM on every call, which is also why the date this has already computed is
  # handed to #due_order rather than left for it to ask again.
  def dated_rules_for(pool)
    (@dated_rules ||= {})[pool.id] ||= pool.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, calculator_for_budget(budget).due_date] }
      .sort_by { |budget, due_on| calculator_for_budget(budget).due_order(due_on) }
  end

  # Sorted for the same reason #waterfall is. This is a rendered list, and `all_pools`
  # carries no ORDER BY, so without this its order is whatever Postgres hands back —
  # which is heap order, and a plain UPDATE relocates a row in the heap. Renaming a pool
  # would reshuffle the attention list with no change to what actually needs attention.
  # Priority first because the list answers "what do I deal with", and that is the order
  # the user already ranked these in.
  def attention_pools
    by_priority(all_pools.select { |pool| status_for(pool).needs_attention? })
  end

  # Fills top-down by priority, exactly as a distribution would, so the user sees
  # who gets paid first and where the money ran out.
  #
  # Per account, not from one global figure. The spec dropped cross-account transfers —
  # money stays where it is, and a user who physically moves it records that — so a single
  # pot would have this screen predict a distribution nobody can perform: an envelope in
  # Checking shown as funded out of cash sitting in Savings. With one account, which is the
  # common case, the per-account bookkeeping is a no-op.
  #
  # Memoised because #shortfall and #covered? both derive from these rows, so a Home render
  # asks for them three times over. The rows are a pure function of already-memoised inputs,
  # but PoolCalculator#balance is not itself memoised — recomputing would be five aggregate
  # queries per account, three times, for an identical answer.
  def waterfall
    @waterfall ||= fill_waterfall
  end

  # WHERE THE MONEY RAN OUT, or nil when there is no such moment. The rule itself is Waterfall's
  # — the distribution screen draws the same line off the same reader — and only the GATE is
  # Home's, because it is genuinely different here.
  #
  # `accounts.one?`: each account drains its own pot, so with several there is no single moment
  # the money ran out — a pool in Ally funded at zero would print the line above rows in Checking
  # that were funded in full. Grouping the waterfall by account is the real answer and belongs to
  # a later plan; until then the per-row figures carry it.
  #
  # `covered?`: the waterfall renders on a covered period too, and there the index finds nothing,
  # falls back to `rows.length` and draws "ran out here · $0.00 unfunded" under the last row of a
  # screen where nothing ran out at all.
  def cutoff
    return nil unless accounts.one? && !covered?

    Waterfall.cutoff(waterfall) { |row| [row[:funded], row[:short]] }
  end

  # DOES THE BUDGET FIT THE INCOME — a question about the shape of the rules, not about this
  # afternoon's cash.
  #
  # REDEFINED off `Budget.steady_need`. It used to compare `total_required`, which is THIS
  # period's ask — catch-up on anything behind, zero on anything already funded — and the two
  # diverge in both directions on the same budget: a period spent catching up on a slipped bill
  # reported "your budget doesn't fit your income" at someone whose rules fit it comfortably, and
  # the period right after a distribution reported nothing at all on a budget that does not fit.
  # Neither reading is what §9 promises, and the second is the dangerous one — the whole point of
  # the check is that reallocation cannot fix a budget that does not fit.
  #
  # Nothing changes retroactively for any existing user: `typical_income` had a column, a
  # validation and this reader but NO WRITER anywhere in the app until the Budget page's
  # declaration form landed alongside this change, so every user's `typical_income` was nil and
  # this method has been unconditionally false in production. The band below it is new ground.
  #
  # `today` rather than `Date.current`, because this presenter is built against a clock and a
  # dated one-off rule's steady claim depends on how many periods are left before it.
  #
  # BOTH HALVES OF THE DECLARATION, income AND cadence — the same gate
  # `BudgetPagePresenter#declared?` applies, because it is the same question. Income with a blank
  # cadence is a reachable state (the declaration form offers "Not set", and a request example
  # pins that clearing the period keeps the income), and in it `Budget.steady_need` falls back to
  # treating the period as a calendar month. That fallback is right for a per-rule normaliser and
  # useless as a verdict: "$1,668 a period" at a user who has not said how long a period is states
  # a figure with no unit, and this band delivers the verdict WITHOUT the figures that would
  # justify it. `/budget` already refuses to print those figures; Home refusing to print the
  # verdict from them is the same refusal.
  #
  # Memoised, and the `false` case has to be memoised too — `||=` would recompute the whole sum on
  # every call for exactly the users who answer false. Task 9 adds a second caller on this page.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    @structurally_underwater =
      user.typical_income.present? &&
      user.period_cadence.present? &&
      Budget.steady_need(user, today: today) > user.typical_income.to_d
  end

  # WHAT MOVING MONEY IN WOULD ACTUALLY CLOSE — PoolStatus#funding_gap, not #amount.
  #
  # The two coincide on :overdrawn, :behind and :wont_make_it, and those are the only attention
  # states whose ROW prints a figure at all (`overdrawn $80.00`, `behind $385.00`; the other two
  # print a date), so the button and the label beside it still name one number.
  #
  # They diverge on :overdue, and taking #amount there was a measured defect: the demo's Renters
  # Insurance holds every penny of a $180 premium that has simply not been paid, and Home offered
  # "Take $180.00 from Ally Savings buffer" — a real mistake proposed to fix an imaginary problem,
  # which would have left the envelope holding $360 against a $180 bill. #funding_gap returns zero
  # there, and the band says what the bill actually needs instead. See _attention.html.erb.
  #
  # `.round(2)` so the THREE places this figure lands cannot disagree: the button's label (rounded
  # by number_to_currency), the link's `amount=` (rounded by Fix#amount_param) and the damage
  # preview (which is computed from whatever is passed to ReallocationPresenter). Measured on the
  # demo's Car Insurance, whose :behind amount is $553.84615384615… — the preview was computed
  # against the repeating figure while the button next to it moved $553.85. Display-identical
  # either way; the point is that the link and its own preview describe one move.
  def fix_amount_for(pool) = status_for(pool).funding_gap.round(2)

  # POOLS IN THE SAME ACCOUNT WITH ENOUGH FREE MONEY, IN THE ORDER THE REALLOCATION SCREEN OFFERS
  # THEM.
  #
  # `free_amount` — balance less what EVERY rule holds — and not the other two readers, which
  # answer different questions and coincide with this one only at zero (amendment B). Task 7 gates
  # a USER-INITIATED move on the source's balance, because there the app states the damage rather
  # than forbidding the move; here the app is PROPOSING, so it must not propose robbing an envelope
  # that is counting on the money. Two thresholds for two different acts, deliberately.
  #
  # THAT GATE IS ALSO WHY A FIX'S DAMAGE SENTENCE IS USUALLY JUST A BALANCE ARROW, which is a
  # property of gating on `free_amount` rather than an oversight, and worth knowing before anyone
  # tries to make the preview say more. `free = max(balance − Σ rule amounts, 0)`, so a move of
  # `amount ≤ free` leaves every rule still taking its full amount: nothing can slip and #required
  # cannot change. Task 7 found the same shape in its own brief (see Candidate) and corrected its
  # gate to the balance, because a USER's move should be allowed and costed. A SUGGESTION is the
  # other way round — the app proposing a move should propose one that costs nothing — so the gate
  # stays and the quiet sentence is the right trade. The one shape that escapes it is a dateless
  # savings goal near its target, whose #goal_required reads the balance directly.
  #
  # A pool whose own status needs attention is excluded outright: proposing to rob an envelope that
  # is itself behind is not a fix. That takes an overdrawn account out with it, which is right —
  # #account_pots already refuses to fund from one.
  #
  # `PoolMovement#crosses_accounts?` decides "same account", not a `account_id ==` of my own: an
  # account sits inside no other account and stands in as its own container, which is the part a
  # second implementation gets wrong, and it is the same reader the write path is refused by. It
  # also means an ACCOUNT is a candidate for the envelopes inside it.
  #
  # THE ORDER IS ASKED OF ReallocationPresenter, NOT DECIDED HERE. It used to be richest-first with
  # a `[priority, name]` tie-break of its own, and on the demo that proposed a $950 house down
  # payment four times over while $330 of Checking buffer sat unoffered — the screen the button
  # opens ranks the buffer first, so the button and its own destination named different sources.
  # ::source_order is the one place that ranking lives; it is a total order (Pool validates name
  # uniqueness per user), so it is also the tie-break amendment D asks for.
  def fix_candidates_for(pool)
    (@fix_candidates ||= {})[pool.id] ||= compute_fix_candidates(pool)
  end

  # The one fix a problem row renders. nil `candidate` is the no-source case (amendment C).
  #
  # nil OUTRIGHT for a pool with no account, which is a different thing and was measured being got
  # wrong: no account's money can reach an orphan whatever anyone moves, so there is no amount to
  # name — and PoolStatus#amount would hand back the pool's own BALANCE rather than a gap, because
  # an owed orphan is usually :saving and that state's figure is what it holds. On the demo seeds
  # that read "Retirement Supplement … $545.00", the pool's balance, offered as the size of its
  # problem. The band prints the step that does fix it instead; see _attention.html.erb.
  #
  # `fetch` with a block rather than `||=`, because nil is a real answer here and `||=` would
  # rebuild it on every hit.
  def fix_for(pool)
    @fixes ||= {}
    @fixes.fetch(pool.id) { @fixes[pool.id] = orphan_pools.include?(pool) ? nil : build_fix(pool) }
  end

  private

  # THE LATCH ITSELF, memoised: #awaiting_opening_balance? is asked once per account this screen
  # renders, and every account but main gets a `false` from the first half of that predicate
  # before this one is ever reached — but on the account that IS main, re-querying it per call
  # would be a second wasted SELECT with no other reader on Home already having proven the answer.
  #
  # `Category.opening_balance`, NOT a hand-rolled `exists?(name: …)`: that scope is
  # CASE-INSENSITIVE, matching `Category`'s own uniqueness validation, so a user who already has a
  # category spelled "opening balance" reads as latched here exactly as it would refuse a second
  # `create!` — one rule, asked the one place it lives, rather than a presenter-side copy that
  # could disagree with the model's own idea of a duplicate name.
  #
  # `defined?` rather than `||=`: the open latch (no such category yet) is `false`, the common
  # case for as long as onboarding is unfinished, and `||=` would re-run the EXISTS on every hit.
  def opening_balance_recorded?
    return @opening_balance_recorded if defined?(@opening_balance_recorded)

    @opening_balance_recorded = user.categories.opening_balance.exists?
  end

  # ONE CLOCK FOR THE SCREEN, built off the accounts this presenter has already loaded so the
  # service asks the database for no ids of its own.
  def distribution_clock
    @distribution_clock ||= DistributionClock.new(user: user, account_ids: accounts.map(&:id), today: today)
  end

  def compute_fix_candidates(pool)
    amount = fix_amount_for(pool)
    return [] unless amount.positive?

    fundable_by(pool).select { |source| free_amount_for(source) >= amount }
      .sort_by { |source| ReallocationPresenter.source_order(source) }
  end

  def fundable_by(pool)
    reachable_pools.reject { |source| source == pool || status_for(source).needs_attention? }
      .reject { |source| PoolMovement.new(from_pool: source, to_pool: pool).crosses_accounts? }
  end

  # Every pool the money could come from, accounts included. Assembled from the two lists Home
  # already holds rather than re-queried, so this costs no query of its own and shares both memos.
  def reachable_pools = @reachable_pools ||= accounts + all_pools

  def free_amount_for(pool) = (@free_amounts ||= {})[pool.id] ||= calculator_for(pool).free_amount

  # ONE ReallocationPresenter FOR ONE ROW, and #source_for rather than #sources: the list reader
  # would build a Candidate — with its damage, four calculators deep — for every sibling envelope
  # in the account, on a screen that renders one button. Home's per-row cost is already a live
  # concern on this plan (amendment E).
  def build_fix(pool)
    amount = fix_amount_for(pool)
    return Fix.new(pool: pool, amount: amount, candidate: nil, covered: true) if covered_by_waterfall?(pool)

    source = fix_candidates_for(pool).first
    Fix.new(
      pool: pool,
      amount: amount,
      candidate: source && damage_reader(pool, source, amount).source_for(source),
      covered: false
    )
  end

  # WHETHER THE NEXT DISTRIBUTION ALREADY SOLVES THIS, so the band does not talk the user into a
  # move they do not need to make. Ruling 4 said do not offer money to a bill that already has it;
  # this is the same principle one step out — do not offer money to a bill that is ABOUT to have
  # it. The move is not free: the source loses money it was holding for its own rule.
  #
  # READ OFF #waterfall, WHICH IS THE PROPOSAL THIS SCREEN IS ALREADY RENDERING, and deliberately
  # not a fresh AllocationCalculator. Two reasons, and the second is the load-bearing one:
  #
  #   The waterfall band sits a few inches below this row on the same screen. A second reader here
  #   could say "the next distribution funds this in full" above a row reading `$0.00 of $300.00`
  #   — a screen contradicting itself in two adjacent bands, which is the exact defect class
  #   `ReallocationPresenter.source_order` was extracted to close one ruling ago.
  #
  #   And "the same proposal the distribution screen would render" is now a property this task
  #   PROVED rather than assumed: #waterfall computes `required` with `net_of_sweep: true` and
  #   #account_pots adds the sweeps, and spec/system/home/fixes_spec.rb pins
  #   `home.shortfall == proposal.rows.sum(&:short)` against AllocationCalculator, per account, in
  #   both sweep shapes — and `home.available == proposal.available` wherever that available is
  #   non-negative, which is the whole of the scope that claim holds over (see #available).
  #   Reaching for a fresh proposal would be a THIRD reader on one screen.
  #
  # NO ROW MEANS NOT COVERED, which is the safe direction and the right one for both shapes that
  # reach it. An ACCOUNT is never a waterfall row (#fill_waterfall spans #all_pools, which excludes
  # them), and a distribution does not repay an overdraft — it funds envelopes OUT of the account —
  # so an overdrawn account keeps its button. A pool asking for nothing is rejected from the rows
  # too, and that pool is already handled one branch earlier by PoolStatus#funding_gap.
  def covered_by_waterfall?(pool)
    row = waterfall_rows_by_pool[pool.id]

    row.present? && row[:short].zero?
  end

  def waterfall_rows_by_pool
    @waterfall_rows_by_pool ||= waterfall.index_by { |row| row[:pool].id }
  end

  # THE SCREEN'S OWN LEDGER GOES WITH IT, and that is the whole of what `ledger:` is for. One of
  # these is built per problem row (see #build_fix), and each used to build a PoolBalanceLedger of
  # its own over `user.pools` — the same 22 pools #ledger already covers, at the same moment, with
  # no `as_of` on either. Measured on Home: three ledgers and nine grouped maxima, now one and
  # three.
  #
  # SHARING IS SAFE HERE BECAUSE HOME WRITES NOTHING. A ledger is a snapshot memoised at its first
  # read (PoolBalanceLedger#totals), so handing one across a write would hand out figures from
  # before it; this presenter renders a GET and the fix buttons are links, so there is no write for
  # the snapshot to fall the wrong side of.
  #
  # #reachable_pools is `accounts + all_pools`, i.e. every pool the user has, and
  # ReallocationPresenter#all_pools is `user.pools` — the same set, so no source or destination
  # falls outside it. It would not cost accuracy if one did: #terms_for hands back nil for an
  # unknown pool and the calculator runs its own five aggregates.
  def damage_reader(pool, source, amount)
    ReallocationPresenter.new(
      user: user, to_pool: pool, from_pool: source, amount: amount, today: today, ledger: ledger
    )
  end

  # Account-less pools are not rows here at all.
  #
  # They used to be, funded at zero, which put their ask into #shortfall. That was wrong in
  # both directions. A gap means money you need and do not have, but an orphan's money may
  # be sitting in Checking already with nowhere to go — a setup problem whose fix is
  # assigning the pool, not finding more cash. And a row funded at zero at priority 1 drags
  # the "ran out here" cutoff above rows that were funded in full, on a screen whose entire
  # job is showing where the money goes. #orphan_pools names them on the attention list
  # instead, and #total_required still counts what they ask for.
  # A pool that asks for nothing is not a row either, and the reason is what it looked like on
  # a screen: "$0.00 of $0.00", and below the "ran out here" line, which reads as money DENIED
  # rather than money not wanted. This band answers where the money goes; a pool with no ask
  # is not part of that story, and the pools band below already shows it.
  #
  # Rejected after the fill, never before it, so the pot still drains in strict priority
  # order. Arithmetic-neutral either way — a zero-need row contributes 0 to `needed`, `funded`
  # and `short` alike, so #shortfall, #projected_buffer and #orphan_required cannot move.
  def fill_waterfall
    pots = account_pots
    fundable = by_priority(all_pools.reject { |pool| pool.account_id.nil? })
    fundable.map { |pool| waterfall_row(pool, pots) }.reject { |row| row[:needed].zero? }
  end

  # Spends `pots` down as it goes, which is why the caller maps in priority order and rejects
  # afterwards: each row is funded out of what the rows above it left behind.
  def waterfall_row(pool, pots)
    needed = required_for(pool)
    pot = pots.fetch(pool.account_id, 0.to_d)
    funded = pot.clamp(0.to_d, needed)
    pots[pool.account_id] = pot - funded
    { pool: pool, needed: needed, funded: funded, short: needed - funded }
  end

  # What each account can actually fund, keyed by account id.
  #
  # Clamped at zero, never netted. An overdrawn account is a debt to surface, not a source
  # to spend from: letting a -$400 balance cancel $400 of a healthy account's cash gives a
  # number that is true about net worth and false about what can be allocated, and this
  # screen exists to answer the second question. The overdraft still has to be shown — it is
  # the loudest state in the app — but as its own account's :overdrawn status, not as a
  # quiet subtraction from somebody else's headline.
  #
  # Deliberately NOT memoised: #fill_waterfall spends this hash down as it fills, so handing
  # out a shared instance would leave #available summing the leftovers rather than the cash.
  #
  # THE SWEEP IS ADDED BEFORE THE CLAMP, NOT AFTER IT, and the order is the whole of whether
  # #shortfall survives this change. Clamping first — `max(balance, 0) + sweeps` — would hand an
  # account $300 in the red and $100 of closed envelopes a $100 pot, funding rows out of money
  # that is still paying off an overdraft. Inside the clamp, a swept overdraft stays a pot of
  # zero, which is exactly what AllocationCalculator#fill produces from its own unclamped
  # `balance + total_swept` (every row clamps against a negative remaining and funds nothing).
  def account_pots
    accounts.to_h do |account|
      pot = current_buffer_for(account) + sweeps_into(account)
      [account.id, [pot, 0.to_d].max]
    end
  end

  # What the next distribution hands back to one account's buffer.
  #
  # PER ACCOUNT, though the brief allowed one global sum. Sweeps cross no account boundary, so
  # the two figures are equal — a budget pool cannot be account-less (Pool validates it) and a
  # savings pool never sweeps (PoolCalculator#period_closed? is false by TYPE), so the orphans a
  # global sum would add contribute provably zero. Scoped anyway because #account_pots is what
  # #fill_waterfall drains, and a global figure would put cash from one account's closed envelope
  # into another account's pot — which is the cross-account funding #fill_waterfall's own comment
  # exists to prevent, and it would move #shortfall.
  #
  # Read off #calculator_for, the same plain calculator every other reader on this screen shares:
  # a `net_of_sweep` one RAISES here by construction, and rightly — the sweep it names has already
  # been subtracted, so asking again derives a second, smaller one.
  def sweeps_into(account)
    sweeps_by_account.fetch(account.id, 0.to_d)
  end

  def sweeps_by_account
    @sweeps_by_account ||= all_pools.group_by(&:account_id).transform_values do |pools|
      pools.sum(0.to_d) { |pool| calculator_for(pool).sweepable_amount }
    end
  end

  # The in-memory twin of the `Pool.by_priority` scope, and the one place the tie-break
  # lives. Priority alone is not a total order: ties would fall through to database order,
  # which is the defect Plan 1 shipped in its allocation waterfall — random UUID bytes
  # deciding which envelope got funded, so the same pool reported different figures on
  # consecutive page loads with no data change. `name` makes the tie a stable, explainable
  # rule instead. PoolCalculator#budgets_by_due_date and PoolStatus#anchored_budgets both
  # guard the same hazard at their own level.
  def by_priority(pools) = pools.sort_by { |pool| [pool.priority, pool.name] }

  # Memoised per pool. #total_required and #waterfall both ask every pool what it needs,
  # and each `pool.calculator` is five balance queries plus a per-rule sort — Home would
  # run the whole lot twice for every envelope on the screen, and two calculators over the
  # same pool could in principle disagree. Same reasoning as PoolStatus#pool_calculator.
  #
  # THE FIVE QUERIES ARE NOW ONE LEDGER'S SHARE OF FIVE. The memo above only ever stopped this
  # screen building the same calculator twice; it did nothing about the other seventeen pools,
  # each paying five aggregates of its own. Home is the widest iteration in the app — every pool
  # the user has, plus every account — so it is the screen the batching was built for.
  def calculator_for(pool)
    (@calculators ||= {})[pool.id] ||= pool.calculator(today: today, terms: ledger.terms_for(pool))
  end

  # ONE LEDGER FOR THE WHOLE SCREEN, over exactly the pools this screen asks about.
  #
  # #reachable_pools rather than #all_pools: accounts are pools too and Home reads their balances
  # for the buffer band, so a ledger scoped to the envelopes alone would leave every account
  # unbatched — correct, since #terms_for hands back nil for a pool it does not know and the
  # calculator then runs its own five, but it is the whole buffer band paying full price.
  #
  # Lazy, like everything else here. Home writes nothing, so there is no deletion for a snapshot
  # to fall the wrong side of; the laziness is only so a presenter built and never rendered costs
  # nothing.
  def ledger = @ledger ||= PoolBalanceLedger.new(reachable_pools)

  # Keyed by the record, not by id: an unsaved rule has no id, and `nil` as a cache key
  # would hand every such rule the first one's calculator.
  def calculator_for_budget(budget)
    (@budget_calculators ||= {})[budget] ||= budget.calculator(today: today)
  end

  # THE POST-SWEEP ASK, which is the one the button on this screen would actually act on.
  #
  # A plain #required reads the LIVE balance, and at proposal time a closed envelope's leftover is
  # still sitting in it — so Groceries holding $85 of last period's money against a $400 rate rule
  # asked for $315 here while the distribution screen asked $400, and the $85 was swept away
  # between the two. Not recoverable by adding the sweep back afterwards: on a mixed envelope,
  # removing the swept money changes which rules #allocated_balances fills and by how much, so
  # only substituting the balance and re-reading gives the right answer. Same reader, same reason
  # and same shape as AllocationCalculator#ask_calculator_for.
  #
  # A SECOND MEMO rather than a flag on #calculator_for, because the two calculators answer
  # different questions and the flagged one may not be asked either of the sweep's own questions —
  # #period_closed? and #sweepable_amount raise on it, and this screen asks both.
  #
  # `terms:` HERE TOO, and this is the half of Home the brief's caller list did not name — stated
  # as an extension rather than folded in quietly. Threading only #calculator_for took Home from
  # 440 queries to 364 on the demo seeds; these calculators are the expensive ones, because a
  # `net_of_sweep` calculator is TWO sets of five aggregates (the projection builds a plain twin
  # to derive its sweep, see PoolProjection#twin) and #total_required asks one of
  # every pool the user has. Same ledger, same pool, same `as_of` — the terms are identical by
  # construction, and #calculator_for's own memo already proves the two objects may share them.
  def ask_calculator_for(pool)
    (@ask_calculators ||= {})[pool.id] ||=
      pool.calculator(today: today, net_of_sweep: true, terms: ledger.terms_for(pool))
  end

  # `[required, 0.to_d].max`, THE GUARD AllocationCalculator#fill ALREADY HAD AND THIS SCREEN DID
  # NOT, and it is the same reachable shape rather than a defensive flourish.
  # PoolCalculator#goal_required returns `[rate, remaining].min`, so a savings goal carrying a
  # rule with a negative amount asks for a negative figure — and #waterfall_row's
  # `pot.clamp(0.to_d, needed)` raises ArgumentError on it. Measured, not assumed:
  # `BigDecimal("100").clamp(BigDecimal("0"), BigDecimal("-150"))` raises, and the example in
  # spec/system/home/attention_spec.rb reproduces it through `update_column` past Budget's
  # validation, exactly as AllocationCalculator's own does. Home is the root route, so this took
  # out the whole app rather than one screen.
  #
  # HERE RATHER THAN AT #waterfall_row's CLAMP, because #total_required reads the same figure and
  # a negative there quietly UNDERSTATES what the user owes — a wrong number is worse than a
  # crash on a money screen. One floor, every Home reader.
  #
  # NOT pushed down into PoolCalculator#required, which would make the two floors one function
  # and is the wrong trade on this branch: spec/services/allocation_calculator_spec.rb pins
  # `calculator.required == -150` on exactly this fixture, deliberately, so the raw reader stays
  # raw and each READ path floors where it clamps. The two now agree because they are the same
  # expression over the same `net_of_sweep` reader, not because they were merged.
  def required_for(pool)
    (@required ||= {})[pool.id] ||= [ask_calculator_for(pool).required, 0.to_d].max
  end

  # `:account` is eager-loaded for #fundable_by, which asks PoolMovement#crosses_accounts? once
  # per candidate per problem — a lazy association there is one SELECT per pool per row.
  def all_pools
    @all_pools ||= user.pools.where.not(pool_type: :account).includes(:budgets, :account).to_a
  end
end
