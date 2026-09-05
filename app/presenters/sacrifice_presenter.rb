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

  def initialize(user:, today: user.today)
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

  # THE CUT LIST: the anchorless rules, biggest per-period claim first.
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
  #   EVERY RULE INSIDE `rules_need` IS ON THE PAGE, in one list or the other. The pool era spelled
  #   an exception here for a rule on an account-less pool — a real claim no distribution could
  #   reach — and the shape is gone; what the sentence was protecting survives as the rule itself:
  #   nothing counted in the headline may be missing from the rows beneath it (see #rows_total).
  #
  # Biggest claim first because the page answers "what do I sacrifice" and the largest cut is the
  # first thing anyone looks for. `[-claim, owner name, id]` is a total order — two rules can share
  # a claim and a category — so the list cannot reshuffle between page loads on unchanged data,
  # which is the defect Plan 1 shipped in its waterfall.
  def cuttable_rows = rows.select(&:cuttable?)

  # THE RULES THAT CANNOT MOVE, each saying which kind of immovable it is. Same order as the cut
  # list, and every rule the user owns is in exactly one of the two lists — see
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
    @rows ||= rules
      .map { |budget| Row.new(budget: budget, claim: budget.steady_ask(user, today: today), reason: reason_for(budget)) }
      .sort_by { |row| [-row.claim, owner_name(row.budget), row.budget.id] }
  end

  # THE NAME THE TIE-BREAK SORTS ON — the category that holds the money (two-ledger spec §3). The
  # pool arm behind it went with `budgets.pool_id` (Task 8). `to_s` because an owner-less rule is
  # `Budget#must_have_a_category`'s refusal rather than something to crash a page over — and
  # `&.` because that refusal is skipped entirely on a schema rewound past the column.
  #
  # Same order `BudgetPageHelper#budget_rule_name` reads the owner in, for the same reason: the row
  # this key sorts is the row that helper labels.
  def owner_name(budget) = budget.category&.name.to_s

  # ** ONLY A REPEATING DATED RULE IS FIXED (fix round 1 — MED-4). ** `:fixed` is the spec's own
  # marking for a claim this page may not offer to cut: the rent comes round every month whatever
  # anybody decides, and a screen offering to trim it would be offering something the user cannot do.
  #
  # ** A ONE-OFF IS CUTTABLE, AND THE TWO SHAPES ARE WHY IT HAD TO BE SAID AGAIN. ** It answered
  # `:dated` — uncuttable-but-for-a-different-reason — and that was harmless while a one-off was a
  # single bill on a day. A GOAL is a one-off now (two-shapes §2), so the marking silently took every
  # savings goal off the cut list: measured, a household declaring $2,050 with $1,900 of repeating
  # bills and one "$5,000 by Jun 1 2027" goal asking $151.52 a period was $1.52 underwater with
  # NOTHING the page would let it cut — a sacrifice view whose whole subject is closing that gap,
  # unable to name the one claim that could close it.
  #
  # A one-off IS a decision: it happens once, on a day the user chose, and moving the day or the
  # figure is exactly what this page exists to offer. `Budget#cadence` is the one place the schedule
  # cascade lives, so the test is asked of it rather than re-read off the three columns.
  def reason_for(budget)
    return nil if budget.anchor_date.blank? || budget.cadence == :one_off

    :fixed
  end

  # EVERY RULE THE USER OWNS, scoped exactly as `Budget.steady_need` scopes its own sum — the same
  # `for_user` and nothing on top of it — so the rows and the figure they must add up to are drawn
  # from one population. A second pass over rows `steady_need` has already loaded, and deliberately:
  # the alternative is this page summing the rules itself, which is the one thing amendment A
  # forbids.
  #
  # `where.not(pool_id: nil)` IS GONE, AND ITS DELETION IS WHAT KEEPS #rows_total TRUE (two-ledger
  # spec §3). It excluded the category-mode CAP, a shape deleted a plan ago, and `steady_need`'s own
  # copy of it went with the cap; kept here it would now exclude exactly the rules this branch
  # writes — every category-owned rule — so the cut list would be missing rows the headline above it
  # counted, which is the one defect `#rows_total` exists to catch.
  #
  # THE OWNER IS PRELOADED, matching `ClaimLedger#rules` — which is what `Budget.steady_need` iterates
  # since the fix wave — exactly. `Budget#user` walks the category, and `#steady_ask`'s one-off branch
  # builds a `ClaimCalculator` that asks `budget.user` for its period boundaries and its own day.
  #
  # ** THIS CLASS DOES NOT BATCH, AND THE COST IS STATED, MEASURED AND PINNED RATHER THAN HIDDEN
  # (fix wave — INFO). ** The whole page costs SIX statements: `.steady_need`'s ledger loads the
  # rules with its `includes(:item, category: :user)` preload, and this reader loads the same set
  # again with its own — the deliberate second pass argued for above.
  #
  # ** A ONE-OFF RULE COSTS NOTHING EXTRA, and the sentence here used to say it cost two. ** That
  # was true while `#steady_ask`'s one-off arm read `#planned_this_period` — a spending query and an
  # adjustment query per rule. Fix wave 2 (MED-A) moved the arm onto `ClaimCalculator#standing_ask`,
  # which reads two columns and the period grid and nothing else, so the calculator that arm builds
  # is an object rather than a query. Measured and pinned in `sacrifice_presenter_spec`: one one-off
  # costs six statements and five cost six. If the duplicate load ever bites, the fix is to iterate a
  # `ClaimLedger` here the way `.steady_need` does — never a second figure computed a second way.
  def rules
    @rules ||= Budget.for_user(user).includes(:item, category: :user).to_a
  end
end
