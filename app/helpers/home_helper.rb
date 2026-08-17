# frozen_string_literal: true

# The row vocabulary of Home's bands. See the UI design spec §4.4.
#
# HomeHelper rather than ApplicationHelper (which the brief suggested) for two reasons: it
# is the helper Rails always mixes into home views whatever `include_all_helpers` is set to,
# which was the brief's whole objection to PoolsHelper; and ApplicationHelper is already at
# rubocop's Metrics/ModuleLength limit, so this vocabulary does not fit there without
# starting to delete other people's comments.
module HomeHelper
  # `period_closed:` APPENDS ` · last period` rather than replacing the figure. Plan 2b
  # decision 1: the leftover is still physically in the envelope until a distribution moves
  # it, so rendering `$0` here would put the screen at odds with the ledger and break
  # `Σ pools == your bank balance`. "$60.00 left · last period" is true about the amount AND
  # about which period it belongs to, and creates the same pressure to distribute.
  #
  # It is a suffix on every state, not just :left_to_spend, because a closed period is a fact
  # about the money rather than about how the pool is doing — an overdrawn envelope whose
  # period has ended is both things at once, and the row has room to say so.
  def pool_status_label(status, period_closed: false)
    label = pool_state_label(status)

    period_closed ? "#{label} · last period" : label
  end

  # `strftime("%b %-d")` rather than `l(date, format: :short)`: no view in this app formats
  # a date through I18n, and the locale's :short renders "Mar 01" where the spec's row
  # vocabulary reads "Mar 1". Same format string as WeeklyCalendarPresenter#range_label.
  #
  # Split from #pool_status_label rather than nested inside it because the seven states plus
  # the closed-period suffix put the one method past rubocop's complexity limit — and the two
  # answer different questions anyway: this one is how the pool is doing, its caller adds
  # which period the money belongs to.
  def pool_state_label(status)
    case status.state
    when :overdrawn then "overdrawn #{number_to_currency(status.amount)}"
    when :overdue then "overdue · was #{status.due_on.strftime("%b %-d")}"
    when :wont_make_it then "won't make it · #{status.due_on.strftime("%b %-d")}"
    when :behind then "behind #{number_to_currency(status.amount)}"
    when :saving then saving_label(status)
    when :left_to_spend then "#{number_to_currency(status.amount)} left"
    else "#{number_to_currency(status.amount)} · on track"
    end
  end

  # What an expanded row calls one of a pool's rules.
  #
  # An item names itself. An item-less rule used to render the literal word "Rule", which on
  # screen reads as missing data rather than as information — so it is named by its SHAPE
  # instead, because the row already prints its amount and its date on the other side and how
  # often it comes round is the only thing the line was still missing.
  #
  # A LOOKUP ON `Budget#cadence` below the item branch, not a predicate cascade of its own: this
  # and `BudgetPageHelper#budget_rule_basis` used to hold the same four-branch classification in
  # the same hazard-ordered sequence. The classification is the record's, the wording is this
  # screen's — Home NAMES a rule, the Budget page says what an amount is per.
  def pool_rule_label(budget)
    return budget.item.name if budget.item.present?

    case budget.cadence
    when :per_paycheck then "Per period"
    when :monthly then "Monthly"
    when :one_off then "One-off"
    else "Every #{budget.interval_months} months"
    end
  end

  # Both forms of the seventh state read as accumulation; NEITHER may read as money to spend,
  # which is the entire reason the state exists (principle 2). Progress against the goal when
  # there is one, because "$424 of $2,400" answers the question a saver is actually asking;
  # "saved" when there is no target to measure against, since "$424 of $0.00" answers nothing.
  def saving_label(status)
    return "#{number_to_currency(status.amount)} saved" unless status.target.to_d.positive?

    "#{number_to_currency(status.amount)} of #{number_to_currency(status.target)}"
  end

  # A row on Home's attention list can be in trouble for a reason PoolStatus does not model:
  # the pool belongs to no account, so no account's money can reach it. That is a setup
  # problem, not a funding one (HomePresenter#fill_waterfall says why it is not a shortfall),
  # and a pool can be both unassigned and overdrawn — so the status is still said when it
  # has one.
  # THE FIX BUTTON'S OWN LABEL — spec §4.2's `[ Take $300 from Rent ]`.
  #
  # Named through `reallocation_pool_name`, which is this app's one answer to what a pool is
  # CALLED when it is one end of a movement: an account stands in for its buffer, so the button
  # reads "Take $300.00 from Checking buffer" and the screen it opens says the same. "Checking"
  # alone would name the whole account, envelopes included, which is not the money being taken.
  def fix_button_label(fix)
    "Take #{number_to_currency(fix.amount)} from #{reallocation_pool_name(fix.source)}"
  end

  # WHY THIS PROBLEM HAS NO BUTTON, and never merely that it has none (amendment C). A row that
  # falls silent here reads as a rendering that failed rather than as an answer.
  #
  # Every sibling in the account was asked and none of them has this much spare, which is worth
  # saying with both the account's name and the figure, so the reader can see what would have had
  # to be there. The other no-button case — a pool with no account — never reaches this method:
  # HomePresenter#fix_for returns nil for it and the band prints the setup step instead.
  #
  # `pool.account || pool` for the container, matching PoolMovement#containing_account: an account
  # sits inside no other account and stands in as its own, so an overdrawn Checking asks its own
  # envelopes and its sentence names itself.
  def fix_gap_sentence(fix)
    container = fix.pool.account || fix.pool
    "Nothing in #{container.name} has #{number_to_currency(fix.amount)} spare to move."
  end

  def pool_problem_label(status, orphan: false)
    return pool_status_label(status) unless orphan
    return "no account · #{pool_status_label(status)}" if status.needs_attention?

    "no account — nothing can fund it"
  end
end
