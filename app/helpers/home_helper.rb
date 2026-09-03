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

  # THE STATES A "THIS PERIOD" BAR HAS ALREADY SAID (answers-first spec §4). `left to spend` IS the
  # bar read backwards — `$90.00 left` is the $310-of-$400 row's own remainder — and `saving` is the
  # goal bar's own two figures (`$424.00 of $2,400.00`), so printing either beside the bar would be
  # the screen answering one question twice in two denominations. That is the exact defect the
  # inverted presentation was adopted to remove, so the silence is the design rather than a tidy-up.
  PERIOD_ROW_SILENT_STATES = [:left_to_spend, :saving].freeze

  # THE SMALL CLAUSE AFTER A "THIS PERIOD" BAR — the row vocabulary surviving "where it earns its
  # place" (spec §4). nil where it earns none, and the view renders no element at all there.
  #
  # THREE ANSWERS, AND THEY ARE THREE DIFFERENT SENTENCES RATHER THAN ONE SAID THREE WAYS:
  #
  #   NOTHING for the two states the bar has already stated (see the constant above) — except that
  #     ` · last period` SURVIVES THERE ALONE. Which period the money belongs to is a fact about the
  #     MONEY rather than about how the category is doing, the bar cannot carry it, and it is the one
  #     thing standing between a quiet row and a user surprised by the next distribution taking $400
  #     back. It is also what keeps the cross-screen pin honest: /budget prints `$400.00 left · last
  #     period` for the same category on the same afternoon, and a Home row silent about the period
  #     would be the two screens disagreeing about the same money.
  #   `on track`, THE WORD WITHOUT THE MONEY, for the one quiet state that is genuinely additional:
  #     whether a dated bill is on schedule is not a fact the bar carries. `pool_state_label` would
  #     print `$2,000.00 · on track`, and that amount is the HOLDING while the bar's is the
  #     SPENDING — two money figures from two different questions, an inch apart, which is the pair
  #     this screen has already shipped once under one noun.
  #   THE WHOLE LABEL, BOTH SUFFIXES, for a state that needs attention. Here the figure IS the news
  #     (`overdrawn $80.00`, `behind $385.00`) and it is not the bar's figure, so nothing is said
  #     twice — and this row renders inches from the trouble strip's row about the same category, so
  #     the two must read identically or the screen disagrees with itself. `pool_status_label` with
  #     both suffixes threaded off the ONE row object is what makes that structural.
  #
  # THE DATE RIDES ON THE QUIET ARM ALONE, which is `HomePresenter::Row#due_marker?`'s rule re-housed
  # for the row type that replaced it: an attention row has already printed its date inside the
  # label, and `overdrawn $50.00 · Oct 17` would date a debt with a deadline belonging to something
  # else.
  def period_row_clause(row)
    status = row.status
    return quiet_period_marker(status) if PERIOD_ROW_SILENT_STATES.include?(status.state)
    return ["on track", status.due_on&.strftime("%b %-d")].compact.join(" · ") unless row.needs_attention?

    pool_status_label(
      status,
      period_closed: status.period_closed?,
      changed_after_distributing: row.changed_after_distributing?
    )
  end

  # The whole of what a bar-silent row still has to say. nil is the ordinary answer; `last period` is
  # `pool_status_label`'s own suffix standing on its own, because there is no state word in front of
  # it to hang off.
  def quiet_period_marker(status) = status.period_closed? ? "last period" : nil

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

  # THE FIX BUTTON'S OWN LABEL — spec §4.2's `[ Take $300 from Rent ]`.
  #
  # `fix.source.name` IS THE CANDIDATE'S OWN NAME, and that is the whole of the naming problem now.
  # It went through `PoolMovementsHelper#reallocation_pool_name` because a pool needed a noun for
  # the money inside it — an account stood in for the cash no envelope had claimed, so the button
  # had to name that remainder rather than read "Checking", which would have named the envelopes
  # too. Nothing contains
  # anything on the purpose ledger: a source is a category or it is AVAILABLE, and
  # `ReallocationPresenter::Root#name` answers "Available" for exactly the reason that class is a
  # null object rather than a `nil`.
  def fix_button_label(fix)
    "Take #{number_to_currency(fix.amount)} from #{fix.source.name}"
  end

  # WHY THIS PROBLEM HAS NO BUTTON, and never merely that it has none (amendment C). A row that
  # falls silent here reads as a rendering that failed rather than as an answer.
  #
  # Every other party was asked — AVAILABLE and every holder category — and none of them has this
  # much spare, which is worth saying with the figure so the reader can see what would have had to
  # be there.
  #
  # NO CONTAINER TO NAME (Task 6). This read "Nothing in Checking has $300.00 spare", because a move
  # could not leave the account the envelope sat in. An allocation crosses nothing (two-ledger spec
  # §2), so the set that was asked is the whole of what the user has, and naming an account would
  # narrow a sentence that is no longer narrow.
  def fix_gap_sentence(fix)
    "Nothing has #{number_to_currency(fix.amount)} spare to move."
  end

  # ── `#pool_problem_label` IS DELETED (answers-first Task 2), and the property it existed for is
  # not lost — it became structural. It forced `period_closed:` off the status so that Home's
  # attention band could not omit the suffix the categories band printed inches below; the strip
  # that replaced that band renders `shared/_holding_status` instead, which threads BOTH suffixes off
  # ONE row object (`HomePresenter::Row`). A caller no longer chooses which suffixes to pass, it
  # chooses which OBJECT to pass, and an object missing an answer raises at render. That partial's
  # own header carried this method as its ONE documented exception; the exception is gone with it.
end
