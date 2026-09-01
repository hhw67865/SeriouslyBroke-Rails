# frozen_string_literal: true

# THE SACRIFICE VIEW (spec §9). Reallocation cannot fix a budget that does not fit an income, so
# this is the screen that answers the only question left: what do I cut?
#
# READ-ONLY, AND MORE STRICTLY SO THAN THE OTHER PRESENTERS ON THIS PLAN (plan decision 3). Home
# and the Budget page write nothing themselves but link to screens that do; this one links only to
# the rules' own edit forms, and the dial above them is arithmetic in the browser over figures
# printed here. Nothing on this page is persisted, so `Σ pools == your bank balance` is untouched
# by construction rather than by care.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §9
class SacrificePresenter
  # ONE RULE ON THE PAGE, cuttable or not.
  #
  # `claim` is `Budget#steady_ask` — the rule's PER-PERIOD claim, which is the unit the whole page
  # and its dial work in. It is NOT `budget.amount`: a $1,500 monthly Rent rule claims $692.31 from
  # a biweekly period, and a cut list denominated in sticker prices would have the user "free"
  # $1,500 out of a $2,400 period by touching one rule. The row prints the rule's own unit
  # beside the claim (`budget_rule_basis`) so the edit form it links to is not a surprise.
  #
  # `reason` is nil for a cuttable rule and a symbol for one that is not, and it travels on the
  # ROW rather than on the section because the two uncuttable kinds are uncuttable for different
  # reasons and the spec marks them differently ("can't cut — dated" against "fixed"). Pretending
  # rent is optional would be a lie; pretending a dentist appointment is a rate would be another.
  Row = Data.define(:budget, :claim, :reason) do
    def cuttable? = reason.nil?

    # PLAIN, UNDELIMITED DIGITS FOR THE DIAL, because `parseFloat` is what reads this attribute and
    # it stops at the first character it does not understand.
    #
    # `DigitsHelper.digits`, which is where this reader lives now: it used to be
    # `SacrificePresenter.digits` and moved out whole when the §6 impact card became its second
    # consumer. Its whole rationale — the thousands separator, the expired BigDecimal reason, why
    # ActiveSupport rather than ActionView — moved with it and is written down there. See the
    # task-9 report for the measurement.
    def claim_param = DigitsHelper.digits(claim)
  end

  attr_reader :user, :today

  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  # THE SAME TWO READERS THE BUDGET PAGE'S STRUCTURAL CHECK PRINTS, never a sum of this page's
  # own. `Budget.steady_need` is the one answer to "what do your rules claim from a period"
  # (Task 4's ruling, recorded in its own comment) and `user.typical_income` is the one answer to
  # the other half. Two screens asking the same question of two different sums is how the Budget
  # page tells a user their budget misses by $291.92 and this page offers them $250 of cuts to
  # close it.
  def rules_need = @rules_need ||= Budget.steady_need(user, today: today)

  # `.to_d` because `#gap` subtracts this from a BigDecimal and the `money` column's cast does not
  # reach an in-memory user assigned `typical_income: 2400`, which holds the Integer.
  def typical_income = user.typical_income&.to_d

  # HOW FAR UNDERWATER, per period. Positive means the rules do not fit.
  #
  # `typical_income.to_d` rather than a guard, and the nil case is stated rather than defended
  # against: `nil.to_d` is zero, so an undeclared user's gap is their whole `rules_need`. That is
  # not a verdict anyone should read — it is the figure for "you bring in nothing", which nobody
  # said — which is exactly why #underwater? tests #declared? FIRST and the controller refuses the
  # route before a single figure is printed. The arithmetic stays total; the gate does the work.
  def gap = @gap ||= rules_need - typical_income.to_d

  # The gap as digits the dial can subtract from — see `DigitsHelper.digits`.
  def gap_param = DigitsHelper.digits(gap)

  # BOTH HALVES OF THE DECLARATION, income AND cadence — the same condition
  # `BudgetPagePresenter#declared?` applies and the same one `HomePresenter#structurally_underwater?`
  # is gated on, because it is the same question. Without a cadence `Budget.steady_need` still
  # answers (it falls back to treating the period as a calendar month), and that fallback is right
  # for a per-rule normaliser and useless as a verdict: "$291.92 underwater every period" at a user
  # who has not said how long a period is states a figure with no unit, and this whole screen is
  # that figure.
  def declared? = user.typical_income.present? && user.period_cadence.present?

  # §9'S GATE, and the one state this screen renders in.
  #
  # The FIGURES behind it are single-reader (see #rules_need and #typical_income); what is said a
  # third time on this branch is only the COMPARISON, and it is spelled here rather than borrowed
  # from either of the other two presenters because neither of them belongs to this route:
  # HomePresenter builds a ledger over every pool the user owns and BudgetPagePresenter loads every
  # rule with four preloads, and a controller reaching for one of those to ask a two-column
  # question would pay for a screen it is not rendering. `gap.positive?` and
  # `steady_need > typical_income` are the same test over the same BigDecimals.
  def underwater? = declared? && gap.positive?

  # THE CUT LIST: anchorless pool-mode rules, biggest per-period claim first.
  #
  # TASK 4'S RULING, INHERITED RATHER THAN RE-DECIDED (see `Budget.steady_need`'s comment, which
  # says so in as many words). Three boundaries, each with its own reason:
  #
  #   CATEGORY CAPS ARE NOT HERE AT ALL, not even as fixed rows. A cap is a spending limit on
  #   tracking, not a claim on income — no distribution has ever asked for a penny on account of
  #   one — so it is absent from `rules_need`, and cutting one would free exactly nothing. A row
  #   offering to cut $600 of "Food & Dining" would be offering money that does not exist.
  #
  #   ANCHORED RULES ARE UNCUTTABLE. Rent on the 16th is what it is; a dentist appointment on the
  #   19th is a date, not a rate. They are still LISTED (see #fixed_rows) because the page owes the
  #   user the whole of what their rules claim, and marked as such because "pretending rent is
  #   optional would be a lie" is the spec's own wording.
  #
  #   ORPHAN POOL RULES ARE CUTTABLE like any other rate. A rule on an account-less pool is a real
  #   claim the user declared and it is inside `rules_need`; leaving it out of the cut list would
  #   put money in the gap that nothing on this page could reach.
  #
  # Biggest claim first because the page answers "what do I sacrifice" and the largest cut is the
  # first thing anyone looks for. `[-claim, pool name, id]` is a total order — two rules can share
  # a claim and a pool — so the list cannot reshuffle between page loads on unchanged data, which
  # is the defect Plan 1 shipped in its waterfall.
  def cuttable_rows = rows.select(&:cuttable?)

  # THE RULES THAT CANNOT MOVE, each saying which kind of immovable it is. Same order as the cut
  # list, and every pool-mode rule the user owns is in exactly one of the two lists — see
  # #rows_total, which is `rules_need` and is asserted to be.
  def fixed_rows = rows.reject(&:cuttable?)

  # EVERY DOLLAR THIS PAGE COULD FREE, which is the ceiling the unwinnable case is measured against.
  def cuttable_total = @cuttable_total ||= cuttable_rows.sum(0.to_d, &:claim)

  # THE UNWINNABLE CASE (spec §9: "if every available cut still leaves a gap, the app says so
  # instead of offering false comfort").
  #
  # Σ cuttable claims < gap, with cutting every rule to ZERO as the ceiling — which is not a
  # realistic budget and is not meant to be. The claim the page makes is the strongest one
  # available: even the impossible cut does not close this. That is the only version of the
  # sentence that cannot be argued with, and a softer ceiling would be exactly the false comfort
  # the spec names.
  def unwinnable? = cuttable_total < gap

  # WHAT IS LEFT WHEN EVERYTHING CUTTABLE IS CUT — the number the unwinnable statement prints, and
  # it is a NUMBER rather than a shrug because a screen that says "this cannot be fixed" without
  # saying by how much has told the user nothing they can act on. Negative when the budget is
  # winnable, which is why only the unwinnable branch prints it.
  def unclosable = gap - cuttable_total

  # `rules_need` reassembled from the rows this page actually prints, so the two cannot drift.
  #
  # Not rendered anywhere: it exists so the presenter spec can pin the identity
  # `Σ cuttable + Σ fixed == rules_need` on real fixtures. The page's whole credibility rests on
  # its rows being the need — a user who adds the column up and lands somewhere else has been
  # shown a list that is missing a rule — and an identity nothing asserts is a coincidence.
  def rows_total = rows.sum(0.to_d, &:claim)

  private

  def rows
    @rows ||= pool_rules
      .map { |budget| Row.new(budget: budget, claim: budget.steady_ask(user, today: today), reason: reason_for(budget)) }
      .sort_by { |row| [-row.claim, row.budget.pool.name, row.budget.id] }
  end

  # `:dated` and `:fixed` are the spec's own two markings, and they are told apart by SHAPE rather
  # than by a second reading of the three schedule columns: `Budget#cadence` is the one place that
  # cascade lives (`basis_per_period?` first, then the interval), and a private copy here would
  # reopen exactly the seam Task 7 closed when it collapsed two helpers into it.
  #
  # A one-off is dated in the sense a user can act on: it happens once, on a day, and the money has
  # to be there by then. Everything else anchored recurs — rent, insurance — and is fixed in the
  # sense that the bill is the bill.
  def reason_for(budget)
    return nil if budget.anchor_date.blank?

    budget.cadence == :one_off ? :dated : :fixed
  end

  # POOL-MODE RULES ONLY, scoped exactly as `Budget.steady_need` scopes its own sum — same
  # `for_user`, same `where.not(pool_id: nil)` — so the rows and the figure they must add up to
  # are drawn from one population. A second pass over rows `steady_need` has already loaded, and
  # deliberately: the alternative is this page summing the rules itself, which is the one thing
  # amendment A forbids.
  #
  # `pool: :user` because `Budget#steady_ask` divides by `user.periods_per_year` and `#cadence`
  # reads nothing off the pool, while the one-off branch builds a BudgetCalculator that asks
  # `budget.user` for its period boundaries and `budget.item` for what has been paid. `:account`
  # is not preloaded: no reader here touches it.
  #
  # `category: :user` BESIDE IT, and the `where.not(pool_id: nil)` above is not a reason to skip it
  # (two-ledger spec §3, fix round 2): these rows have a pool, but `Budget#user` asks the CATEGORY
  # first, and Task 1's migration wrote a `category_id` onto every one of them. Filtering on one
  # column says nothing about which column the owner is read through — `Budget.steady_need` loads
  # this same population with the same pair, and this page exists to add up to that figure.
  def pool_rules
    @pool_rules ||= Budget.for_user(user).where.not(pool_id: nil)
      .includes(:item, pool: :user, category: :user).to_a
  end
end
