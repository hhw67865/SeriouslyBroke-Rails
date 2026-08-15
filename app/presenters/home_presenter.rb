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
  # "for each account, render pools_for" would render these nowhere at all — while they
  # still occupy a waterfall row and count toward #total_required. Savings pools stay
  # account-less until Plan 3's backfill, so today this is the ordinary shape for a
  # savings goal, not a rare edge: Tasks 6/7 need an unassigned group to put them in.
  def orphan_pools
    by_priority(all_pools.select { |pool| pool.account_id.nil? })
  end

  # `.to_d`, not the raw balance: PoolCalculator#balance is five `sum(:amount)` calls, and
  # an account holding no entries at all makes every one of them return the Integer literal
  # 0. #available seeds its own sum so it is safe either way, but this is a public money
  # reader and Task 8's views divide by it for the buffer bar — Integer division there
  # would truncate silently on exactly the accounts that are emptiest.
  def buffer_for(account) = calculator_for(account).balance.to_d

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
  # filled", which is the only question a distribution can act on. It also puts an
  # account-less pool's ask into the gap, where it belongs, instead of letting another
  # account's cash silently absorb it.
  #
  # The difference between the two figures is money stranded in the wrong account. With one
  # account they are always equal, so it only surfaces in the multi-account case — where the
  # view owes the user an explanation of why subtracting the headlines gives another number.
  #
  # No `max` clamp is needed: every row's `short` is `needed - funded` where `funded` is
  # clamped to at most `needed`, so no row can contribute a negative.
  def shortfall = waterfall.sum(0.to_d) { |row| row[:short] }

  def covered? = shortfall.zero?

  # Views MUST use this rather than calling pool.status directly. PoolStatus defaults
  # to Date.current, so a bare call in a partial would compute against a different day
  # than this presenter whenever `today` is injected — and disagree silently.
  def status_for(pool)
    @statuses ||= {}
    @statuses[pool.id] ||= pool.status(today: today)
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

  def fill_waterfall
    pots = account_pots
    by_priority(all_pools).map do |pool|
      needed = required_for(pool)
      # A pool with no account has nothing to draw on and funds zero, rather than
      # silently helping itself to the first account's pot. Savings pools stay
      # account-less until Plan 3's backfill, so this is reachable today.
      pot = pots.fetch(pool.account_id, 0.to_d)
      funded = pot.clamp(0.to_d, needed)
      pots[pool.account_id] = pot - funded
      { pool: pool, needed: needed, funded: funded, short: needed - funded }
    end
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
    accounts.to_h { |account| [account.id, [buffer_for(account), 0.to_d].max] }
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

  def required_for(pool) = (@required ||= {})[pool.id] ||= calculator_for(pool).required

  def all_pools
    @all_pools ||= user.pools.where.not(pool_type: :account).includes(:budgets).to_a
  end
end
