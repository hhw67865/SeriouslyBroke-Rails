# frozen_string_literal: true

# The sacrifice view's row copy.
module SacrificesHelper
  # Why a rule is not in the cut list, and never merely that it is not: a row that fell silent would
  # read as a checkbox that failed to render. `Row#reason` is a symbol, so the words live here.
  FIXED_REASON = "fixed — the bill is what it is"

  # The rule's own unit beside its per-period claim, and only where the two differ: a per-period
  # rule IS denominated in periods, so the clause would be one number said twice.
  def sacrifice_rule_unit(row)
    return nil if row.rule.cadence == :per_period

    "· #{number_to_currency(row.rule.amount)} #{rule_basis(row.rule)}"
  end
end
