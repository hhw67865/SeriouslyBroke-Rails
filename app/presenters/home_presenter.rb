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

  # `.to_d`, not the raw balance: PoolCalculator#balance is five `sum(:amount)` calls, and
  # an account holding no entries at all makes every one of them return the Integer literal
  # 0. #available seeds its own sum so it is safe either way, but this is a public money
  # reader and Task 8's views divide by it for the buffer bar — Integer division there
  # would truncate silently on exactly the accounts that are emptiest.
  def buffer_for(account) = calculator_for(account).balance.to_d

  # Unclaimed cash across every account — what a distribution has to work with.
  def available
    @available ||= accounts.sum(0.to_d) { |account| buffer_for(account) }
  end

  def total_required
    @total_required ||= all_pools.sum(0.to_d) { |pool| required_for(pool) }
  end

  def shortfall = [total_required - available, 0.to_d].max

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
  def waterfall
    remaining = available
    by_priority(all_pools).map do |pool|
      needed = required_for(pool)
      funded = remaining.clamp(0.to_d, needed)
      remaining -= funded
      { pool: pool, needed: needed, funded: funded, short: needed - funded }
    end
  end

  def structurally_underwater?
    user.typical_income.present? && total_required > user.typical_income.to_d
  end

  private

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
