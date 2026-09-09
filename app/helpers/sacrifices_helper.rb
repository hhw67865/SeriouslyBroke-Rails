# frozen_string_literal: true

# The sacrifice view's row copy. See the UI design spec §9.
module SacrificesHelper
  # WHY THIS RULE IS NOT IN THE CUT LIST, and never merely that it is not — a row that fell silent
  # here would read as a checkbox that failed to render.
  #
  # ** ONE MARKING WHERE THERE WERE TWO (fix round 1 — MED-4). ** §9 split them: "can't cut — dated"
  # for a one-off and "fixed" for everything else anchored. A ONE-OFF IS CUTTABLE now — a goal is a
  # one-off (two-shapes §2), and a page whose whole subject is closing a structural gap cannot refuse
  # to name the one claim that could close it — so `:dated` is never returned and the only rows that
  # reach here are the repeating bills whose amount somebody else sets.
  #
  # The symbol is `SacrificePresenter::Row#reason`, decided there off `Budget#cadence`; only the
  # words are this module's.
  def sacrifice_fixed_reason(_row) = "fixed — the bill is what it is"

  # THE RULE'S OWN UNIT BESIDE ITS PER-PERIOD CLAIM — "$1,500.00 a month" against the "$692.31 a
  # period" this page adds up — and only where the two are actually different things.
  #
  # A per-period rule IS denominated in periods, so the clause rendered "$3,000.00 a period ·
  # $3,000.00 / period": one number twice, on every rate row on the screen, which reads as a
  # rendering fault rather than as information. Measured on the rendered page, exactly as
  # `BudgetPageHelper#pool_balance_clause` was.
  #
  # Gated on the CADENCE and not on the two figures being equal, because they can coincide by
  # arithmetic while still meaning different things: a one-off with one period left to save claims
  # its whole amount, and "$300.00 a period · $300.00 once" is the row saying something true and
  # necessary — the money is wanted now AND the bill never comes again.
  def sacrifice_rule_unit(row)
    return nil if row.budget.cadence == :per_period

    "· #{number_to_currency(row.budget.amount)} #{budget_rule_basis(row.budget)}"
  end
end
