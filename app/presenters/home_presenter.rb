# frozen_string_literal: true

# Everything the Home screen renders. Read-only: this plan adds no write paths.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4
class HomePresenter
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
  # `.to_d`, not the raw balance: PoolCalculator#balance is five `sum(:amount)` calls, and
  # an account holding no entries at all makes every one of them return the Integer literal
  # 0. #available seeds its own sum so it is safe either way, but this is a public money
  # reader and Task 8's views divide by it for the buffer bar — Integer division there
  # would truncate silently on exactly the accounts that are emptiest.
  def current_buffer_for(account) = calculator_for(account).balance.to_d

  # Unclaimed cash across every account — an honest answer to "what do I have".
  #
  # Note this is NOT `total_required - shortfall`: see #shortfall for why the gap is
  # derived from the rows instead, and why the two can legitimately disagree.
  def available
    @available ||= account_pots.values.sum(0.to_d)
  end

  # What every rule asks for this period — an honest answer to "what do I owe",
  # regardless of which account the money would have to come from.
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

  # Views MUST use this rather than calling pool.status directly. PoolStatus defaults
  # to Date.current, so a bare call in a partial would compute against a different day
  # than this presenter whenever `today` is injected — and disagree silently.
  def status_for(pool)
    @statuses ||= {}
    @statuses[pool.id] ||= pool.status(today: today)
  end

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

  private

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
  def account_pots
    accounts.to_h { |account| [account.id, [current_buffer_for(account), 0.to_d].max] }
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

  def required_for(pool) = (@required ||= {})[pool.id] ||= calculator_for(pool).required

  def all_pools
    @all_pools ||= user.pools.where.not(pool_type: :account).includes(:budgets).to_a
  end
end
