# frozen_string_literal: true

# The reallocation screen's copy: what a move would cost, why a source cannot make it, and what
# happened once it did. See the UI design spec §4.2, §5 and the two-ledger spec §2.
#
# EVERY METHOD IS PREFIXED `allocation_` RATHER THAN `reallocation_`, and the prefix is doing real
# work rather than following a convention: `PoolMovementsHelper` is still mixed into the same view
# context for Home's fix buttons until Task 6, its methods take the pool-era `Candidate`, and Rails
# includes every helper module into every view. Two modules defining `reallocation_damage_sentence`
# would leave the include order deciding which Candidate shape the app can render — silently, since
# both objects answer `#damage`. Task 6 deletes `PoolMovementsHelper`; renaming these back afterwards
# is optional and cosmetic.
module AllocationsHelper
  # THE DAMAGE STATEMENT — the sentence this screen exists to be able to say before the money moves.
  # Spec §5's shape:
  #
  #   Car $1,340 → $1,122 — Maintenance slips to $494/$800 · +$27/period
  #
  # Three clauses, and the last two are printed ONLY when they are true of this move. A category
  # whose ask does not change says nothing about a period, exactly as the distribution screen's
  # consequence line stays off a rate category. The balance arrow is always printed because it is the
  # move itself rather than a consequence of it.
  #
  # AVAILABLE PRINTS THE ARROW AND NOTHING ELSE, by construction rather than by a branch here: it
  # holds money for no rule, so `ReallocationPresenter#root_damage` reports an unchanged ask and no
  # slip, and all three conditionals below are false.
  def allocation_damage_sentence(candidate)
    damage = candidate.damage
    parts = ["#{number_to_currency(damage.balance_before)} → #{number_to_currency(damage.balance_after)}"]
    parts << allocation_slip_clause(damage.slip) if damage.slipped?
    parts << allocation_ask_clause(damage) if damage.ask_changed?
    # The app's own row vocabulary (spec §4.4), not a sentence of its own: the move pushed the
    # category into a state that already exists, and it should read here exactly as it will read on
    # Home half a second later.
    parts << "becomes #{pool_status_label(damage.status_after)}" if candidate.state_changed?
    parts.join(" · ")
  end

  # Both figures, never a delta. `+$27/period` is unreadable without the number it is added to, and
  # the pair is also what makes it obvious that neither side was produced by subtracting the other —
  # they are two independent runs of HoldingCalculator#required.
  def allocation_ask_clause(damage)
    "asks #{number_to_currency(damage.ask_after)} a period instead of " \
      "#{number_to_currency(damage.ask_before)}"
  end

  def allocation_slip_clause(slip)
    "#{allocation_rule_name(slip.budget)} slips to #{number_to_currency(slip.allocated)} " \
      "of #{number_to_currency(slip.budget.amount)}"
  end

  # A RULE NAMED INSIDE A SENTENCE. `HomeHelper#pool_rule_label` is the app's one answer to what a
  # rule is called and is reused rather than replaced, but its item-less fallback is a COLUMN value —
  # "Monthly", "One-off", "Per period" — written to sit beside an amount and a date. Read straight
  # into prose it loses its subject: "Monthly is due Oct 16 and is holding $1,500.00" reads as a
  # sentence about a month.
  #
  # "its … rule" restores the subject for every shape at once, including the named one — "its Vet
  # Visit rule is due Sep 5" — rather than branching on whether the rule happens to have an item,
  # which would be a second copy of pool_rule_label's own branch.
  def allocation_rule_name(budget) = "its #{pool_rule_label(budget)} rule"

  # The destination select's pairs. FLAT, where the pool era grouped by account: there is one root
  # (two-ledger spec §2), so there is nothing left to group by, and AVAILABLE is simply the first
  # option. `#name` and `#id` are answered by the ROOT and by a Category alike, which is the whole
  # reason the root is a null object rather than a `nil`.
  def allocation_destination_options(parties)
    parties.map { |party| [party.name, party.id] }
  end

  # WHY THIS SOURCE IS DISABLED, and never merely that it is. Two different clauses, because they
  # send the user to two different places: "only $116.00 in it" says find another envelope, while a
  # bill's name and date says why what is in it isn't spare.
  #
  # Both where both are true — the amount is the answer to "can it make the move" and the bill is the
  # answer to "why is it so thin", and a row carrying only the first invites the user to conclude the
  # envelope is empty when it is holding $66.00 for a vet visit next month.
  def allocation_reason(candidate)
    [allocation_balance_clause(candidate.holding), allocation_holder_clause(candidate.holder)]
      .compact.join(" · ")
  end

  # "nothing in it", not "$0.00 in it": an empty envelope is a different fact from a thin one, and
  # the figure adds nothing a reader could act on. Overspent lands here too — its own status label on
  # the same row already prints how far under it is.
  def allocation_balance_clause(balance)
    return "nothing in it" unless balance.positive?

    "only #{number_to_currency(balance)} in it"
  end

  # WHAT THIS SOURCE HAS AND WHAT OF IT IS SPARE, on every row that can make the move. Both figures,
  # because they answer different questions and are equal only on a category with no rules at all
  # (and on AVAILABLE, which has none by definition): the holding says whether the move is possible,
  # `free_amount` says whether it costs anything, and the damage line below fires exactly when the
  # second is exceeded.
  def allocation_holding_clause(candidate)
    "#{number_to_currency(candidate.holding)} in it · #{number_to_currency(candidate.free)} of it free"
  end

  # A disabled row is still a row: greyed rather than hidden, so someone who came looking for the
  # envelope they can see on Home finds it here saying why it cannot help.
  def allocation_source_label_class(candidate)
    tone = candidate.affordable? ? "text-gray-900" : "text-gray-400"

    "form-label mb-0 #{tone}"
  end

  # THREE COLOURS FOR THREE DIFFERENT THINGS, and exclusive rather than layered — `class_names` would
  # emit two of these at once on a move that is both promised and state-changing, leaving the
  # stylesheet's declaration order to pick between them.
  def allocation_damage_class(candidate)
    return "text-status-danger" if candidate.state_changed?
    return "text-status-warning" if candidate.promised?

    "text-gray-500"
  end

  # DATED RULES ONLY. Every rule holds money and #free_amount subtracts all of them, but a date is
  # the part that changes what the user should do — "its own bill is due first" is a reason, and
  # "your grocery budget is spoken for" is a restatement of the figure beside it.
  def allocation_holder_clause(holder)
    return nil if holder.nil?

    "#{allocation_rule_name(holder.budget)} is due #{holder.due_on.strftime("%b %-d")} " \
      "and is holding #{number_to_currency(holder.allocated)}"
  end

  # THE OTHER END, said once above the sources. The damage statement is all cost; without this the
  # screen never states what the cost buys, and the state flipping out of `overdue` is the whole
  # reason anyone is on this page.
  def allocation_gain_sentence(gain)
    line = "#{gain.name} #{number_to_currency(gain.balance_before)} → " \
           "#{number_to_currency(gain.balance_after)}"
    return "#{line}." unless gain.state_changed?

    "#{line} — #{pool_status_label(gain.status_before)} becomes #{pool_status_label(gain.status_after)}."
  end

  # WHAT THE MOVE DID, on the screen the user lands on afterwards. Both figures are read back out of
  # the ledger AFTER the write (see AllocationsController#confirmation_for), never off the proposal —
  # the figures a user checks a money action against have to come from the ledger the action wrote.
  #
  # Both ends, because the invariant is that this move created nothing: the two figures are the same
  # money in two places, and a sentence naming only the destination reads as money arriving from
  # somewhere unspecified.
  #
  # A NULL SIDE IS "Available" — the root, which is what NULL means on this table.
  def allocation_confirmation(allocation, source_balance:, destination_balance:)
    source = allocation_party_name(allocation.from_category)
    destination = allocation_party_name(allocation.to_category)

    "Moved #{number_to_currency(allocation.amount)} from #{source} to #{destination}. " \
      "#{source} #{number_to_currency(source_balance)} · #{destination} #{number_to_currency(destination_balance)}."
  end

  # A nil side is AVAILABLE (two-ledger spec §2), and this is the one place that is spelled — the
  # same job `PoolMovementsHelper#reallocation_pool_name` did for an account standing in as its own
  # buffer.
  def allocation_party_name(category) = category&.name || ReallocationPresenter::ROOT.name
end
