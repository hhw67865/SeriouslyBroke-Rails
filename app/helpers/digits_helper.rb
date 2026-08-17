# frozen_string_literal: true

# ONE SPELLING OF "MONEY A BROWSER CAN PARSE", for every figure that crosses into the DOM as a
# data attribute rather than as copy. Two spellings would be two chances to leave the delimiter
# in, and the delimiter is the defect.
#
# EXTRACTED FROM `SacrificePresenter.digits`, which was its first home and never its only one. FOUR
# consumers, and the count is measured rather than claimed — the last two were byte-identical
# copies found by grep when the third was about to become a fourth:
#
#   * `SacrificePresenter::Row#claim_param` / `#gap_param` — the dial's per-period claims and gap,
#   * `EntryImpactPresenter#balance_param` / `#denominator_param` — the §6 impact card,
#   * `HomePresenter::Fix#amount_param` — the attention band's fix links,
#   * `ReallocationPresenter#amount_value` — the reallocation form's amount box (which keeps its own
#     nil guard, because an untouched box is empty and that is true of no other caller).
#
# Every one of them calls the same method now. Four spellings would be four chances to leave the
# delimiter in, and every caller kept its own name and its own behaviour, so no screen changed
# shape.
#
# THE LIVE HAZARD IS THE THOUSANDS SEPARATOR, and it is measured rather than assumed:
# `number_to_rounded` delimits by default, so a $1,500 figure would reach `data-claim` as
# "1,500.00" and `parseFloat("1,500.00")` is 1.5 — a rule offering to free a dollar fifty, or an
# envelope holding one. `delimiter: ""` is the whole of what stops it, and both consumers' specs
# pin a four-figure amount for exactly that reason.
#
# `HomePresenter::Fix#amount_param` gives a second reason — BigDecimal's `to_s` emitting "0.3e3" —
# and ON THIS BRANCH THAT REASON HAS EXPIRED: bigdecimal 4.0.1 prints `BigDecimal("300").to_s` as
# "300.0" and `BigDecimal("692.31").to_s` as "692.31", both of which `parseFloat` reads correctly.
# Recorded rather than relied on. The scaling to two decimals is still wanted (these are money and
# the copy beside them prints cents), and a bigdecimal that went back to scientific notation would
# find this already guarded.
#
# `ActiveSupport::NumberHelper` and NOT ActionView's `number_with_precision`, because the sacrifice
# view's caller is a `Data` object with no view context. The first spelling of this reached for a
# bare `number_to_rounded`, which is the ActiveSupport module's name and not a view helper at all —
# a 500 on the whole page, caught by the first system example that loaded it.
#
# `module_function` so the one definition serves both callers: presenters call
# `DigitsHelper.digits(...)` on the module, and views — which Rails includes every helper into —
# call it bare.
module DigitsHelper
  module_function

  def digits(amount) = ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: "")
end
