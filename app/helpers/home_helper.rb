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
  # `changed_after_distributing:` IS SPEC §8'S ROUGH EDGE, and it is gated on `:behind` HERE rather
  # than at each caller. Rule changes apply immediately, so editing a rule the day after a
  # distribution flips its envelope from `on track` to `behind $50` with no money having moved —
  # and the clause exists to say which of the two kinds of `behind` this is. On any other state it
  # would be an unexplained aside: an `overdue` bill is overdue because it was not paid, and an
  # edited rule has nothing to do with it. One gate, so no caller can put the clause somewhere it
  # does not belong.
  #
  # "CHANGED A RULE HERE" AND NOT §8'S LITERAL "you raised this rule". The spec's sentence claims a
  # DIRECTION and a SUBJECT that the signal behind it cannot supply — a lowered rule moves the same
  # timestamp, and a pool with two rules cannot say which one moved. See `DistributionClock` for
  # both shapes and for the timestamps behind them. The design spec is being corrected to match, as
  # it was over the waterfall band's tense.
  #
  # WHICH CALLERS PASS THIS CLAUSE, and it is not all of them. The three that say how a pool STANDS
  # RIGHT NOW pass it — Home's pools band, Home's attention band (through #pool_problem_label) and
  # the Budget page's group header — because those three render the same envelope on the same
  # afternoon and a clause on one of them alone reads as the app disagreeing with itself. It was
  # missing from two of the three at different times, once between Home and /budget and once
  # between Home's own two bands.
  #
  # The distribution and reallocation screens pass `period_closed:` and NOT this, deliberately.
  # Their rows describe a move that has not happened — `pool_movements_helper`'s sentences are
  # literally "becomes …" — and why the envelope got into its current state is a different subject
  # from what a proposed transfer would do to it. Which period the money belongs to bears on the
  # move; who last edited the rule does not.
  #
  # AFTER the `· last period` suffix, because the two say different kinds of thing and the order
  # is the order a reader needs them: how the pool is doing, WHICH period its money belongs to,
  # then why it is doing that. `behind $50.00 · last period — you changed a rule here after
  # distributing` reads as one sentence; the other order splits the state from its own explanation.
  def pool_status_label(status, period_closed: false, changed_after_distributing: false)
    label = pool_state_label(status)
    label = "#{label} · last period" if period_closed
    label = "#{label} — you changed a rule here after distributing" if changed_after_distributing && status.state == :behind

    label
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

  # BOTH SUFFIXES TRAVEL THROUGH rather than stopping here, and they travel for one reason: the
  # attention band and the pools band render the SAME pool inches apart on one screen — a `behind`
  # envelope is in both by construction, and so is an overdrawn one — so a suffix on one band and
  # not the other reads as the two bands disagreeing about the same pool.
  #
  # `changed_after_distributing:` arrives from the caller because it is a question about the
  # SCREEN's period (see HomePresenter#changed_after_distributing?), which a status cannot answer.
  # `period_closed:` is NOT a keyword here and deliberately so: it is a fact about this pool's own
  # money, `PoolStatus#period_closed?` already carries it off the calculator the status was built
  # from, and a keyword would give a caller the option of omitting it. That option is exactly what
  # went wrong — this method used to pass one suffix and not the other, so one Home render printed
  # `overdrawn $80.00 · last period` in the pools band and `overdrawn $80.00` in the attention band
  # a few inches above it.
  #
  # THE ARGUMENT DOES NOT CARRY UP TO #pool_status_label, AND TAKING IT THERE WOULD RAISE.
  # `PoolStatus#period_closed?` delegates to `PoolCalculator#period_closed?`, which begins with
  # `refuse_when_net_of_sweep` — and the reallocation and distribution screens hand
  # #pool_status_label statuses built `net_of_sweep: true`, which would raise `NetOfSweepError` on
  # the spot. Those screens compute the suffix off a separate PLAIN calculator for exactly this
  # reason (see DistributionPresenter). So the keyword stays a keyword one level up. It is safe
  # HERE because the only caller is Home's attention band, whose statuses come from
  # HomePresenter#status_for and carry no sweep.
  def pool_problem_label(status, orphan: false, changed_after_distributing: false)
    label = pool_status_label(
      status,
      period_closed: status.period_closed?,
      changed_after_distributing: changed_after_distributing
    )
    return label unless orphan
    return "no account · #{label}" if status.needs_attention?

    "no account — nothing can fund it"
  end
end
