# frozen_string_literal: true

# The distribution screen's row copy. See the UI design spec §5.
module DistributionsHelper
  # The states whose label already prints a date of its own — PoolStatus picks the rule that PUT
  # the pool in that state, which is not necessarily the earliest-due one this row's schedule
  # clause describes. Named here rather than string-testing the label for a date, which would be
  # an assertion about a string this module does not own.
  #
  # TWO, not three. `:behind` was in this list on the reasoning that the design spec's §4.4 row
  # vocabulary writes it as `behind $385 · Mar 1` — but `HomeHelper#pool_state_label` prints
  # `behind $385` and no date at all, so listing it suppressed the schedule clause on a row that
  # then had no date anywhere on it: `behind $1,022.22`, about a bill with a due date. Measured
  # on the dated-bill system example, which expected the date and found the bare label.
  DATED_STATES = [:overdue, :wont_make_it].freeze

  # What a waterfall row says about the envelope itself: the app's existing row vocabulary
  # (spec §4.4, `HomeHelper#pool_status_label`), plus the schedule behind the ask.
  #
  # ONE date per row, never two. `behind $385 · Mar 1 · due Feb 14 · 2 periods left` is two
  # different bills' dates side by side, and there is no reading of that row that recovers
  # which is which — so where the state already carries a date, the state's date wins and the
  # schedule clause stays off.
  #
  # The ` · last period` suffix rides along from `pool_status_label`, and it is the clause this
  # screen most needs: it marks exactly the envelopes whose leftover the sources breakdown is
  # about to sweep back.
  def distribution_line_detail(line)
    label = pool_status_label(line.status, period_closed: line.period_closed)
    return label if DATED_STATES.include?(line.status.state) || !line.scheduled?

    "#{label} · due #{line.due_on.strftime("%b %-d")} · #{pluralize(line.periods_left, "period")} left"
  end

  # The buffer target, said as a want rather than as a denominator. `$1,419.00 of $2,000.00`
  # reads as a limit on a figure that has none — the buffer target is a health marker and never
  # a cap (spec §7.1) — so the clause names what it measures or stays off entirely.
  def buffer_target_clause(presenter)
    return "" unless presenter.buffer_target?

    " · you wanted #{number_to_currency(presenter.buffer_target)}"
  end

  # What the row proposes to put in, on the right-hand side. `$315.00 of $400.00` only where
  # the two differ: `$400.00 of $400.00` on a fully funded row is noise, and it is the row that
  # is NOT fully funded that has to stand out on a screen whose job is showing where the money
  # ran out.
  def distribution_line_amount(line)
    return number_to_currency(line.funded) unless line.short?

    "#{number_to_currency(line.funded)} of #{number_to_currency(line.needed)}"
  end
end
