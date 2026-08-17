# frozen_string_literal: true

# The Budget page's row copy. See the UI design spec §8.
module BudgetPageHelper
  # WHAT THE ENVELOPE IS HOLDING, and only where the row has not already said it.
  #
  # `pool_status_label` prints PoolStatus#amount, which IS the balance in four of the seven states
  # — the balance itself in three and its negation on :overdrawn. Printed unconditionally this
  # read "$400.00 left · holds $400.00" and "overdrawn $80.00 · holds -$80.00" — one number twice,
  # on ten of the demo's fourteen groups. Measured on the rendered page, not reasoned about.
  #
  # `PoolStatus#amount_is_balance?` rather than a state list of this module's own. Which states
  # print the pool's money is a fact about `PoolStatus#amount`, and a hand copy of its case
  # statement here would be a second reader free to drift from it the day an eighth state lands.
  # (String-testing the label for a `$` would be worse still — an assertion about a string this
  # module does not own.)
  #
  # The balance is therefore on screen for every pool either way; this clause is what puts it
  # there for the three states whose figure is a bill's shortfall instead.
  def budget_group_balance(group)
    return "" if group.status.amount_is_balance?

    "· holds #{number_to_currency(group.balance)}"
  end

  # WHAT A RULE IS CALLED. The item it pays is the truest name — "Rent Bill" says what the money
  # does — and where there is none the rule is named by whatever owns it, because a rule with no
  # item is the pool's or the category's own rate and the owner IS the subject.
  #
  # Deliberately NOT `HomeHelper#pool_rule_label`, which falls back to the rule's SHAPE
  # ("Every 6 months"). That fallback is right on Home, where a row prints a pool's rules
  # underneath the pool's own name and repeating it would say the name twice. Here the shape is
  # already printed beside the amount by #budget_rule_amount, so the name is free to be the one
  # thing the row was otherwise missing — and an orphan row, which has no group heading above it,
  # has no other way to say whose rule it is.
  def budget_rule_name(budget)
    budget.item&.name || budget.pool&.name || budget.category&.name
  end

  # "$400.00 / period", "$600.00 every 6 months" — the amount and what it is an amount PER.
  # A figure with no basis is unreadable on this page: $600 a period and $600 every six months
  # are the same digits and a twelvefold difference in what the user owes.
  def budget_rule_amount(budget)
    "#{number_to_currency(budget.amount)} #{budget_rule_basis(budget)}"
  end

  # A LOOKUP ON `Budget#cadence`, not a predicate cascade of its own. This module and
  # `HomeHelper#pool_rule_label` used to hold the same four-branch classification, in the same
  # order, each with its own copy of the comment saying why that order is a hazard — so the
  # classification moved to the record whose columns it reads and only the WORDS stayed here.
  # Home names a rule ("Every 6 months"); this says what an amount is per ("every 6 months"),
  # and it is the only one of the two ever asked about a category-mode rule.
  #
  # `:every_n` interpolates the interval here rather than carrying it, so the model's answer
  # stays a fixed set of four.
  def budget_rule_basis(budget)
    case budget.cadence
    when :per_paycheck then "/ period"
    when :monthly then "a month"
    when :one_off then "once"
    else "every #{budget.interval_months} months"
    end
  end

  # WHY THIS RULE IS NOT IN THE FILL ORDER, and never merely that it is not.
  #
  # The account-less clause is Home's own row phrasing, verbatim
  # (`HomeHelper#pool_problem_label`): it is the same fact about the same pool, and two wordings
  # for one setup problem would have the two screens disagree about what the user must do next.
  #
  # A CLAUSE RATHER THAN A SENTENCE, and that is a correction made at the browser. Both reasons
  # were first written as full sentences on their own line under the row; on the demo seeds that
  # rendered the identical sentence seven times down one band, which reads as a rendering fault
  # rather than as seven rules with the same problem. Each row still says why — it says it beside
  # its own name, in the length the rest of this app's rows use.
  def budget_rule_reason(rule)
    return "no account — nothing can fund it" if rule.reason == :no_account

    "caps a category — no envelope to fill"
  end
end
