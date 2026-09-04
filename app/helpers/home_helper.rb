# frozen_string_literal: true

# The row vocabulary of Home's bands. See the UI design spec §4.4.
#
# HomeHelper rather than ApplicationHelper (which the brief suggested) for two reasons: it
# is the helper Rails always mixes into home views whatever `include_all_helpers` is set to,
# which was the brief's whole objection to PoolsHelper; and ApplicationHelper is already at
# rubocop's Metrics/ModuleLength limit, so this vocabulary does not fit there without
# starting to delete other people's comments.
module HomeHelper
  # ** THE STATUS VOCABULARY IS GONE (computed-claims spec §6). ** `#pool_status_label`,
  # `#pool_state_label` and `#saving_label` read a `HoldingStatus` and printed its seven states —
  # `overdrawn`, `overdue`, `won't make it`, `behind`, `saving`, `left to spend`, `on track` — with
  # two suffixes, `· last period` and `— you changed a rule here after distributing`. Every one of
  # those sentences is about money that was MOVED into a category and what a distribution would do
  # to it next, and there are no movements on the purpose side any more (§5). The last screens that
  # spoke it — the categories page's holdings card and `shared/_holding_status` — were converted to
  # §3.4's claim vocabulary in this same commit, so the methods are callerless as well as
  # meaningless.
  #
  # WHAT SURVIVES OF THE SEVEN STATES is two facts about a claim rather than a state machine:
  # `ClaimCalculator#over?` (spent past what the rule allowed) and `#overdue?` (a date already
  # past), rendered by `#claim_trouble_label` below. `#pool_rule_label` is untouched — it names a
  # RULE, which is a question the change of model does not touch.

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

  # THE SCHEDULE CLAUSE UNDER AN ACCRUING ROW (§3.4): `next due Mar 1 · $200.00 per period`.
  #
  # ** THE TENSE IS THE DATE'S OWN (fix round 1 — MED-1). ** A $600 bill due Aug 15, saved in full and
  # never paid, keeps its occurrence anchored where it was (§3.2) — so on Sep 3 this row printed
  # `next due Aug 15`, a date already gone under a word that promises a future one. `was due` is what
  # a past occurrence gets, and the side of `today` it falls on is read off `#overdue?` rather than
  # compared here: that predicate IS `next_due_on < today` (`ClaimCalculator#overdue?`), stated once,
  # so this clause and the trouble label above it cannot disagree about one date on one afternoon.
  #
  # ** WHAT DROPS AND WHAT SURVIVES (fix round 1 — MED-2, a comment that misstated its own code). **
  # It said "nil for a fund already full". It is not, and never was: a full fund's per-period SHARE is
  # zero, so that half of the clause drops and the DATE is printed alone (`was due Aug 15`) — which is
  # exactly the row a user with an unpaid bill needs. nil is returned for a RATE rule only, which has
  # neither half: use-it-or-lose-it accrues toward nothing and is due on no day. The view renders no
  # element at all where this is nil.
  def claim_schedule(line)
    return nil if line.rate?

    [
      line.next_due_on && "#{line.overdue? ? "was due" : "next due"} #{line.next_due_on.strftime("%b %-d")}",
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
