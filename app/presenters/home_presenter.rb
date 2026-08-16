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
  Fix = Data.define(:pool, :amount, :candidate) do
    def source = candidate&.pool

    # Whether moving money is the right kind of answer at all. `amount` is PoolStatus#amount, and
    # the four attention states guard their own figure positive — except :overdue, whose amount is
    # a bill's unpaid remainder and could in principle round to nothing. A "Take $0.00 from
    # Checking" button is worse than no band, so the view renders nothing at all here.
    def actionable? = amount.positive?

    # PLAIN DIGITS FOR THE QUERY STRING, for ReallocationPresenter#amount_value's reason one screen
    # later: `BigDecimal("300").to_s` is "0.3e3", which reaches the link as `amount=0.3e3`. It is
    # read back correctly (`to_d` parses it) but it is the URL the user sees and copies.
    def amount_param = ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: "")
  end

  attr_reader :user, :today

  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  def accounts
    @accounts ||= user.pools.accounts.order(:name).to_a
  end

  def pools_for(account)
    by_priority(all_pools.select { |pool| pool.account_id == account.id })
  end

  # Pools belonging to no account. #pools_for filters on account_id, so a view built as
  # "for each account, render pools_for" would render these nowhere at all. Savings pools
  # stay account-less until Plan 3's backfill, so today this is the ordinary shape for a
  # savings goal, not a rare edge.
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

  # Views MUST use this rather than calling pool.status directly. PoolStatus defaults
  # to Date.current, so a bare call in a partial would compute against a different day
  # than this presenter whenever `today` is injected — and disagree silently.
  def status_for(pool)
    @statuses ||= {}
    @statuses[pool.id] ||= pool.status(today: today)
  end

  # Whether this pool's money belongs to a period that has already ended — what the row marks
  # as ` · last period` and what the next distribution will sweep back.
  #
  # Here rather than in the partial for the same reason as #status_for: PoolCalculator defaults
  # to Date.current, so a view building its own would answer against a different day than every
  # other figure on the screen whenever `today` is injected, and disagree silently. Routed
  # through #calculator_for so it reuses the calculator Home has already built for this pool.
  def period_closed?(pool) = calculator_for(pool).period_closed?

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
  # all anchorless renders its own explanation instead (see _pool_row). The sort key is the
  # triple PoolStatus#anchored_budgets already uses — `pool.budgets` carries no ORDER BY, so
  # without it two rules sharing a due date could swap places between page loads. Memoised
  # because BudgetCalculator#due_date re-runs its paid_since_anchor SUM on every call.
  def dated_rules_for(pool)
    (@dated_rules ||= {})[pool.id] ||= pool.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, calculator_for_budget(budget).due_date] }
      .sort_by { |budget, due_on| [due_on, -budget.amount, budget.id] }
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

  def structurally_underwater?
    user.typical_income.present? && total_required > user.typical_income.to_d
  end

  # WHAT THIS PROBLEM IS SHORT BY, and it is deliberately the figure the row beside it already
  # prints: `overdrawn $80.00` offers to move $80.00, `behind $385.00` offers $385.00.
  #
  # PoolStatus#amount is DEFINED as the number its state is about, so this is one reader rather
  # than a second opinion — and a fix button naming a different figure from the label six pixels
  # to its left is a screen asking the reader to reconcile two numbers.
  #
  # It is the money gap in three of the four attention states by construction (:overdrawn is
  # `-balance`, :wont_make_it is the rule's own shortfall against what it holds, :behind is
  # `expected - allocated`). :overdue is the one that is not: that state is about a DATE and a
  # missing payment, so its figure is the bill's unpaid remainder — which is still what has to be
  # in the envelope before the bill can be paid, and still the right amount to move, but the state
  # itself will not clear until the payment is recorded. The reallocation screen says as much: its
  # Gain sentence prints no state change on an overdue destination.
  #
  # `.round(2)` so the THREE places this figure lands cannot disagree: the button's label (rounded
  # by number_to_currency), the link's `amount=` (rounded by Fix#amount_param) and the damage
  # preview (which is computed from whatever is passed to ReallocationPresenter). Measured on the
  # demo's Car Insurance, whose :behind amount is $553.84615384615… — the preview was computed
  # against the repeating figure while the button next to it moved $553.85. Display-identical
  # either way; the point is that the link and its own preview describe one move.
  def fix_amount_for(pool) = status_for(pool).amount.round(2)

  # POOLS IN THE SAME ACCOUNT WITH ENOUGH FREE MONEY, RICHEST FIRST.
  #
  # `free_amount` — balance less what EVERY rule holds — and not the other two readers, which
  # answer different questions and coincide with this one only at zero (amendment B). Task 7 gates
  # a USER-INITIATED move on the source's balance, because there the app states the damage rather
  # than forbidding the move; here the app is PROPOSING, so it must not propose robbing an envelope
  # that is counting on the money. Two thresholds for two different acts, deliberately.
  #
  # A pool whose own status needs attention is excluded outright: proposing to rob an envelope that
  # is itself behind is not a fix. That takes an overdrawn account out with it, which is right —
  # #account_pots already refuses to fund from one.
  #
  # `PoolMovement#crosses_accounts?` decides "same account", not a `account_id ==` of my own: an
  # account sits inside no other account and stands in as its own container, which is the part a
  # second implementation gets wrong, and it is the same reader the write path is refused by. It
  # also means an ACCOUNT is a candidate for the envelopes inside it — the buffer, the money no
  # envelope has claimed, and what spec §4.2's "money you already have" most often means.
  #
  # THE SORT KEY IS A TRIPLE, not a bare `-free` (amendment D). Two pools with equal free money
  # would otherwise fall through to `user.pools`' order, which carries no ORDER BY — so the same
  # problem would offer different fixes on consecutive loads with no data change, which is the
  # defect Plan 1 shipped in its allocation waterfall. `[priority, name]` is this branch's
  # established tie-break for pools and is what #by_priority already uses.
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

  def compute_fix_candidates(pool)
    amount = fix_amount_for(pool)
    return [] unless amount.positive?

    fundable_by(pool).select { |source| free_amount_for(source) >= amount }
      .sort_by { |source| [-free_amount_for(source), source.priority, source.name] }
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
    source = fix_candidates_for(pool).first
    Fix.new(pool: pool, amount: amount, candidate: source && damage_reader(pool, source, amount).source_for(source))
  end

  def damage_reader(pool, source, amount)
    ReallocationPresenter.new(user: user, to_pool: pool, from_pool: source, amount: amount, today: today)
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
  def calculator_for(pool) = (@calculators ||= {})[pool.id] ||= pool.calculator(today: today)

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
  def ask_calculator_for(pool)
    (@ask_calculators ||= {})[pool.id] ||= pool.calculator(today: today, net_of_sweep: true)
  end

  def required_for(pool) = (@required ||= {})[pool.id] ||= ask_calculator_for(pool).required

  # `:account` is eager-loaded for #fundable_by, which asks PoolMovement#crosses_accounts? once
  # per candidate per problem — a lazy association there is one SELECT per pool per row.
  def all_pools
    @all_pools ||= user.pools.where.not(pool_type: :account).includes(:budgets, :account).to_a
  end
end
