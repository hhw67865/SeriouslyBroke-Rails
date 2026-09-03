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
  # RIGHT NOW pass it — Home's "This period" bars (through #period_row_clause), Home's trouble strip
  # (through `shared/_holding_status`) and the Budget page's group header — because those three
  # render the same category on the same afternoon and a clause on one of them alone reads as the app
  # disagreeing with itself. It was missing from two of the three at different times, once between
  # Home and /budget and once between Home's own two bands.
  #
  # The distribution and reallocation screens pass `period_closed:` and NOT this, deliberately.
  # Their rows describe a move that has not happened — `AllocationsHelper`'s sentences are
  # literally "becomes …" — and why the category got into its current state is a different subject
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

  # ── ** THE CLAIM VOCABULARY (computed-claims spec §3.4). ** ────────────────────────────────────
  #
  # `#period_row_clause`, `#quiet_period_marker` and `PERIOD_ROW_SILENT_STATES` ARE DELETED (Task 3),
  # and the deletion is that Home stopped asking their question rather than that nothing called them.
  # All three read a `HoldingStatus`, whose seven states describe what was MOVED into a category —
  # `left to spend`, `behind`, `· last period`, `— you changed a rule here after distributing`. There
  # are no movements on the purpose side any more (§5), so there is no "last period" money awaiting a
  # sweep, no distribution to have edited a rule after, and nothing "behind" that a transfer could
  # catch up. A claim is a FUNCTION, and the three things it can be is: under its rate, over it, or
  # accruing toward a date. Those are the three sentences below.
  #
  # THE STATUS VOCABULARY ITSELF IS NOT DELETED — the distribute, reallocation and category screens
  # still speak it, and Task 4 is what retires it with them. Home simply stopped.

  # THE FIGURE ON A "THIS PERIOD" ROW (§3.4): `spent of rate` for an envelope, `built up of target`
  # for a fund. ONE method for both because the two are the same shape said about different money,
  # and the caller must not choose the noun — a row that printed "spent" over a fund's running total
  # would be the money screen's oldest lie, that savings are money to spend.
  def claim_figure(line)
    return "#{number_to_currency(line.spent)} of #{number_to_currency(line.accrued)}" if line.rate?

    "#{number_to_currency(line.built_up)} built up of #{number_to_currency(line.target)}"
  end

  # THE SCHEDULE CLAUSE UNDER AN ACCRUING ROW (§3.4): `next due Mar 1 · $200.00 per period`. nil for a
  # rate rule, which has neither — use-it-or-lose-it accrues toward nothing and is due on no day — and
  # nil for a fund already full, whose per-period share is zero and which is waiting to be spent
  # rather than saved into. The view renders no element at all where this is nil.
  def claim_schedule(line)
    return nil if line.rate?

    [
      line.next_due_on && "next due #{line.next_due_on.strftime("%b %-d")}",
      line.per_period.positive? && "#{number_to_currency(line.per_period)} per period"
    ].select { |clause| clause.is_a?(String) }.join(" · ").presence
  end

  # WHAT IS WRONG WITH A CLAIM, IN THE TWO SHAPES §4 SAYS ARE WORTH A HUMAN. The strip and the "This
  # period" row print the SAME string about the same rule inches apart, which is why it is one method:
  # the two said it differently once already, under the status vocabulary this replaces.
  #
  # `over by` IS THE PRE-CLAMP FIGURE — `spent − accrued`, the excess that reduced `free` directly
  # (§3.1). The claim itself is zero in this state, so a figure taken from the claim would print
  # `over by $0.00` on every overspend.
  #
  # `overdue · was Mar 1` KEEPS THE STATUS VOCABULARY'S OWN WORDING for the one state that survives
  # the change of readers unchanged in meaning: a date has passed and the money is not there.
  def claim_trouble_label(line)
    return "over by #{number_to_currency(line.spent - line.accrued)}" if line.over?

    "overdue · was #{line.next_due_on.strftime("%b %-d")}"
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
    when :per_period then "Per period"
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

  # ── `#fix_button_label` AND `#fix_gap_sentence` ARE DELETED (computed-claims Task 3), with the
  # whole fix apparatus they labelled. A "fix" was an ALLOCATION — money moved from one category, or
  # from AVAILABLE, into the one that was short — and §5 leaves the purpose side with no movements at
  # all. There is nothing left to take money FROM, because nothing holds any: a claim is computed, and
  # the only things that change one are a rule, an adjustment (§3.3) or spending less. The strip says
  # so and its one door is the Budget page. `/allocations/new` and the sentences these labelled are
  # still alive for the reallocation screen until Task 4 deletes it.

  # ── `#pool_problem_label` IS DELETED (answers-first Task 2), and the property it existed for is
  # not lost — it became structural. It forced `period_closed:` off the status so that Home's
  # attention band could not omit the suffix the categories band printed inches below; the strip
  # that replaced that band renders `shared/_holding_status` instead, which threads BOTH suffixes off
  # ONE row object (`HomePresenter::Row`). A caller no longer chooses which suffixes to pass, it
  # chooses which OBJECT to pass, and an object missing an answer raises at render. That partial's
  # own header carried this method as its ONE documented exception; the exception is gone with it.
end
