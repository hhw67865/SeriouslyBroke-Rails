# frozen_string_literal: true

# THE CATEGORIES PAGE'S HOLDINGS CARD — what this category's money IS, in the two states an expense
# category can be in. Read-only: it has nothing to write.
#
# ** NOTHING IS HELD ANY MORE, AND THAT IS THE WHOLE OF THIS REWRITE (computed-claims spec §5). **
# The card used to read a `HoldingCalculator` — allocations in, less allocations out, less the
# spending attributed to the category — and stand a `HoldingStatus` beside it. There are no
# movements on the purpose side at all now: a category's money is a CLAIM computed from its rules,
# the calendar, its spending and its dated adjustments (§2), knowable at any instant with nothing
# ever having moved. So there is no balance to read, no allocation to be stranded, no period whose
# leftover awaits a sweep, and no distribution for a rule to have been changed after.
#
# TWO ARMS, AND THE LINE BETWEEN THEM IS STILL `Category#holder?` (§3.2). A category with a
# `funded_since` is one whose rules accrue and whose spending counts against them — that date is
# `ClaimCalculator#accrual_start`, the day the walk opens in. A category without one claims nothing
# whatever has been spent on it, because a claim comes from a rule and a rule on a category with no
# funding date walks no periods at all.
#
# ** A LINE PER RULE, AND THE CARD'S FIGURE IS THEIR SUM (§3.4; Task 3's ruling for Home). ** §3.4's
# sentences are per RULE — `spent of rate` for a rate rule, `built up of target · next due · $X per
# period` for an accruing one — and `Category#claim` is a SUM, so a category carrying a rate rule
# beside an item-backed bill cannot honestly print one figure: the two are denominated in different
# things. `Line` below is the same object shape `BudgetPagePresenter::Rule` and
# `HomePresenter::ClaimLine` are, so `HomeHelper#claim_figure`, `#claim_schedule` and
# `#claim_trouble_label` render all three — one sentence about one rule across the three screens
# that show it, rather than a third vocabulary invented here.
#
# ** A `ClaimLedger`, NOT `Category#claim`, EVEN THOUGH THIS PAGE RENDERS EXACTLY ONE CATEGORY. **
# The old class refused a `CategoryLedger` on precisely that ground — "a ledger's whole point is
# answering for a SET" — and the ground has moved out from under it. The card needs a
# `ClaimCalculator` PER RULE for §3.4's line, and `Category#claim` cannot supply one: it returns the
# sum and nothing else, so going that way means `category.claim` walking every rule once for the
# heading and `Budget#claim_calculator` walking every rule again for the lines — every figure on the
# card computed twice, by two objects, which is exactly how a heading comes to disagree with the rows
# beneath it. `ClaimLedger` answers both off ONE set of calculators, in three grouped statements, and
# `#claim_of_category` is pinned figure for figure against `Category#claim` in `claim_ledger_spec`.
#
# `claims:` IS A SEAM AND NOT A SECOND DOOR, on `ClaimCalculator#spending:`'s own reasoning: the
# categories INDEX renders every category the user owns and `CategoriesController#claim_ledger`
# already holds one ledger for that whole page, so a card there hands its ledger in rather than
# building the thirtieth copy of it. Nothing is passed on the show page and this class builds its
# own; either way there is one ledger per screen.
#
# ** THE TEST IS `Category#building_rule` (rules-own-the-budget spec §5/§7), AND IT IS A QUESTION
# ABOUT A RULE. ** It was `#saving_toward_a_target?` — `holder? && target_amount.present?` — and the
# column it read is one no claim formula consults: `ClaimCalculator#shape` answers `:building` off
# the RULE's `carries_over`, and caps at the RULE's `target_amount`. So the card asks the rule, and
# it asks TWO things where there used to be one — is money building up here, and is there a figure
# it is aiming at — because a building rule may name no target at all (§2.1 row 2). The show card's
# heading, the index card's bar and the entry form's impact card all read the same rule, so a fund
# is a fund on every one of them.
#
# ** AND THE TARGET IS THE FUND'S ALONE (spec §10.5; fix wave — MED-1). ** A ceiling is a ceiling on
# the FUND's built-up, so it is printed only where the building rule is the category's ONLY rule —
# `Category.fund_is_the_whole_category?`, the same test the impact card and the dashboard's savings
# strip apply to their own populations. Beside a sibling bill, Σ claims is not the fund's money and a
# bar drawn against the target would be a fraction of the wrong number.
#
# See docs/superpowers/specs/2026-09-03-computed-claims-design.md §2-§5.
class CategoryBudgetPresenter
  # ** ONE RULE'S LINE ON THE CARD — §3.4'S ROW, IN THE SHAPE THE SHARED HELPERS READ. **
  #
  # The member names are `BudgetPagePresenter::Rule`'s, and the three aliases below it are the same
  # three: `HomeHelper#claim_figure` asks `#rate?`, `#spent`, `#accrued`, `#built_up` and `#target`;
  # `#claim_schedule` asks `#rate?`, `#next_due_on`, `#overdue?` and `#per_period`;
  # `#claim_trouble_label` asks `#over?`, `#spent`, `#accrued` and `#next_due_on`. An object that
  # answered any of them differently would be this card quietly saying a different sentence about a
  # rule than the Budget page says about the same rule on the same afternoon.
  #
  # A `Data` HOLDING FIGURES RATHER THAN THE CALCULATOR ITSELF, on `BudgetPagePresenter::Rule`'s
  # reasoning: `#overdue?` compares against the presenter's `today` — the OWNER's day — and an object
  # free to ask a calculator for more would be free to ask it with a clock of its own.
  Line = Data.define(
    :rule,
    :shape,
    :claim,
    :spent,
    :accrued_this_period,
    :built_up,
    :target,
    :capped,
    :next_due_on,
    :planned_this_period,
    :over,
    :over_by,
    :overdue
  ) do
    def rate? = shape == :rate

    # MONEY THAT SURVIVES THE PERIOD BOUNDARY (rules-own-the-budget spec §2.1 rows 2-5). The same
    # reader the other two §3.4 rows carry: `HomeHelper#claim_schedule` renders all three and asks
    # this to tell a building rule's `+$300.00 per period` from a dated rule's `next due Mar 1`.
    def building? = shape == :building

    # ** IS THERE A FIGURE TO MEASURE AGAINST (fix round 1 — MED)? ** `ClaimCalculator#capped?`,
    # carried onto the row rather than re-derived from `target.nil?`, because "uncapped" is one
    # question the calculator already answers and a second spelling here would be free to drift. An
    # UNCAPPED building rule's `#target` is NIL — there is no ceiling — and `HomeHelper#claim_figure`
    # renders this Data as well as Home's, so it asks this before it prints "of".
    def capped? = capped

    def accrued = accrued_this_period

    def per_period = planned_this_period

    # SPENT PAST WHAT THE RULE HAD — `ClaimCalculator#over?`, the figure BEFORE the clamp at zero,
    # which is the only reader that can tell "spent it exactly" from "spent more than there was".
    def over? = over

    # A DATE THAT PASSED WITH THE MONEY STILL UNSPENT (§3.2).
    def overdue? = overdue

    def trouble? = over? || overdue?
  end

  attr_reader :category, :today

  # `today` DEFAULTS TO THE OWNER'S DAY (`Category#today` → `User#today`) AND IS NOT THE PAGE'S
  # `selected_date`. The category page has a period toggle and can be read for a month that is over;
  # what a category CLAIMS is a fact about NOW — a claim is computed at the instant it is asked for
  # (§2) — and rendering last March's figures beside a live "Rules on the Budget page" button would
  # be the page disagreeing with the screen it links to. The spending figures above this card are
  # the ones the toggle is for.
  def initialize(category:, today: category.today, claims: nil)
    @category = category
    @today = today
    @claims = claims
  end

  # ---- Which state the card is in ---------------------------------------------------------------

  # ONE READER FOR WHICH ARM RENDERS, because the card also stamps the state into the DOM for the
  # specs to scope by, and a `data-` attribute computed separately from the branch is free to name
  # an arm the page did not render — which would make a scoped assertion pass against the wrong
  # state and read as green. Both come from here.
  def state = category.holder? ? :holding : :unfunded

  def holding? = state == :holding

  # `#stranded?` IS DELETED WITH THE MONEY IT DESCRIBED (§5). It was "a non-holder whose BALANCE is
  # not zero" — allocations sitting in a category whose `funded_since` had been cleared, money §2's
  # old partition still counted while every reader had stopped looking at it, with no screen left
  # that could move it back out.
  #
  # NOTHING IS EVER MOVED INTO A CATEGORY NOW, so there is nothing a cleared date can leave behind:
  # the state is unplantable rather than merely unreachable, and the arm is deleted instead of being
  # kept as a belt. What the unfunded arm says is a fact about SPENDING and it stays exactly true —
  # `CategoryLedger::ENTRY_CATEGORY_ID` yields NULL for a NULL `funded_since`, so no rule's lane can
  # contain one of this category's receipts and nothing claims them.
  #
  # ** ITS RULES MAY STILL ACCRUE, AND THAT IS NOT THIS ARM'S SUBJECT. ** A rate rule on a category
  # whose date was cleared goes on claiming its whole rate — `accrual_start` falls back to the rule's
  # own birthday — which is precisely why `BudgetPagePresenter#unfilled_rules` exists to list it.
  # This card is about the CATEGORY, and the honest thing to say about one nothing counts against is
  # that nothing claims its spending; the rule's own state is said on the page that owns rules.

  # ---- The holding arm --------------------------------------------------------------------------

  # ONE LEDGER FOR THE CARD, so the heading, the lines and the bar cannot come from three readings.
  # Built here when the caller hands none in — see the header for why the seam exists.
  def claims = @claims ||= ClaimLedger.new(category.user, today: today)

  # ** WHAT THIS CATEGORY'S MONEY IS (§2) — Σ its rules' claims, off the rows this card already
  # built. ** `BudgetPagePresenter::Group#claim`'s spelling exactly, and for its reason: summing the
  # LINES rather than re-asking `ClaimLedger#claim_of_category` means the figure at the top of the
  # card is arithmetically the list beneath it, so no edit to how a line is built can leave the two
  # describing different money. The two expressions are the same sum over the same calculators.
  def claim = lines.sum(0.to_d, &:claim)

  # THE RULES THAT CLAIM THIS CATEGORY'S MONEY, each as §3.4's row. Off the page's one ledger, never
  # a calculator per line: a card free to build its own would cost a walk per rule and could disagree
  # with the figure above it.
  #
  # ** ORDERED BY THE DATE THE LINE ACTUALLY PRINTS — `BudgetPagePresenter#rule_order`'s key. ** The
  # old spelling was `order(:anchor_date, :created_at)`, the RECORD's anchor, which is not the date a
  # row shows: `ClaimCalculator#next_due_on` rolls the occurrence on PAYMENT rather than on the
  # calendar (§3.2), so a half-paid six-monthly bill prints a date its `anchor_date` does not carry.
  # Ordering by one date and printing the other puts a line above its neighbour for a reason the
  # screen contradicts. The key is total: a rule with no date sorts last (a rate rule is never due),
  # ties break on the larger amount and then on the id, because `budgets` carries no ORDER BY and a
  # plain UPDATE relocates a row in the heap.
  def lines
    @lines ||= claims.rules_of(category).map { |rule| build_line(rule) }.sort_by { |line| line_order(line) }
  end

  # ** DOES ANYTHING HERE NEED A HUMAN — the two facts §4 says are worth one, asked of these rows. **
  # Home's trouble strip and the Budget page's group header fire on exactly this test
  # (`BudgetPagePresenter::Group#needs_attention?`), so the three screens cannot come to different
  # verdicts about one category on one afternoon.
  #
  # It was delegated to `HoldingStatus`, whose seven states were about money that had been MOVED —
  # `behind` was the gap between what the rules had asked for and what a distribution had actually
  # put in, and there are no distributions. A claim can be wrong in two ways and no others: spent
  # past what the rule had (§3.1), or a due date gone by with the bill unpaid (§3.2).
  def needs_attention? = lines.any?(&:trouble?)

  # ---- The building arm -------------------------------------------------------------------------

  # ** IS THIS CATEGORY BUILDING MONEY UP — AND IS THERE A FIGURE IT IS AIMING AT? TWO QUESTIONS
  # (rules-own-the-budget spec §5). ** They used to be one, `Category#saving_toward_a_target?`, and
  # the reason they can no longer be is that a building rule may name NO target (§2.1 row 2): an
  # emergency fund grows for as long as the user keeps it. So the card's heading asks the first
  # question and its bar asks the second, and neither is the other's proxy.
  #
  # ** BOTH ARE READ OFF THE RULE. ** `categories.target_amount` is on its way out (§7) and no claim
  # formula has read it since Task 1 — `ClaimCalculator#shape` answers `:building` off the RULE's
  # `carries_over` and caps at the RULE's `target_amount` — so a card reading the category's column
  # would be drawing a bar against a figure nothing computes.
  def building? = building_rule.present?

  # ** FOUND AMONG THE RULES THIS CARD ALREADY HOLDS, NOT THROUGH `Category#building_rule`. ** The
  # test is the same one (`Budget#builds_up_the_category?`, spelled once on the model); the
  # POPULATION is the page's ledger rather than the category's association, because the categories
  # INDEX renders one of these per card and `category.budgets` is not preloaded there — reading the
  # model's door would be a `SELECT budgets` per card on the one screen that draws every category
  # the user owns. `#lines` is already built from `ClaimLedger#rules_of`, one statement for the whole
  # page, so this costs nothing at all.
  #
  # ** THE LINE AND NOT ONLY THE RULE, since the fix wave. ** The bar's numerator is the FUND's own
  # built-up (`#fund_figure`), which is on the row this card already built — going back to a
  # calculator for it would be the second reading this class was written to avoid.
  #
  # `defined?` rather than `||=`: nil is the ordinary answer (an envelope), and a truthiness memo
  # would re-scan the lines on every one of the five readers below that consult it.
  def building_line
    return @building_line if defined?(@building_line)

    @building_line = lines.detect { |line| line.rule.builds_up_the_category? }
  end

  def building_rule = building_line&.rule

  # ** IS THE FUND THE WHOLE CATEGORY — THE GATE ON EVERY TARGET THIS CARD PRINTS (fix wave —
  # MED-1; spec §10.5). ** `Category.fund_is_the_whole_category?` asked of the rules the page's ONE
  # ledger fetched, which is the same test the entry form's impact card asks of the association and
  # the dashboard's strip asks of its preload — see the model for why the target is a sentence about
  # the fund and not about the category whenever a sibling rule exists.
  def fund_is_the_whole_category? = Category.fund_is_the_whole_category?(rules)

  # ** WHAT THE FUND ITSELF HAS BUILT UP — the numerator of every bar this card draws. ** `#claim` is
  # Σ EVERY rule's claim, and on a category carrying a fund beside a bill those are different money;
  # this is the fund's own figure, off the row already built. The two are equal wherever a bar is
  # drawn at all (`#bar?` requires the fund to be the whole category, and a building rule's claim IS
  # its built-up — `ClaimCalculator#claim`), so no figure on any screen moves: what the spelling buys
  # is that loosening the gate could never silently change what the percentage is a percentage OF.
  def fund_figure = building_line&.built_up

  # THE FIGURE THE FUND IS AIMING AT, or NIL where it names none — AND NIL AGAIN WHERE THE FUND IS
  # NOT THE WHOLE CATEGORY (fix wave — MED-1), because a ceiling printed beside Σ claims is a
  # ceiling on the wrong number. Nil rather than zero, exactly as `ClaimCalculator#target` answers it
  # and for the same reason: zero is a ceiling that has already been reached, and every reader below
  # asks presence before it divides.
  def target
    return nil unless fund_is_the_whole_category?

    building_rule.target_amount&.to_d
  end

  # HOW FULL, AS A WHOLE PERCENT, CLAMPED AT BOTH ENDS — `HoldingCalculator#progress_percentage`'s
  # arithmetic verbatim, with `#fund_figure` where `#balance` stood. Kept to the digit deliberately:
  # the money the numerator names changed, the reading of it did not, and a figure that moved here
  # would have moved for a reason nobody asked for. (It read `#claim` until the fix wave; the two are
  # the same figure on every fixture that reaches this line — see `#fund_figure`.)
  #
  # ZERO FOR AN UNCAPPED FUND, and the card draws no bar there at all (see `#bar?`): a fund with no
  # ceiling is not a fraction of anything, and a track whose fullness means nothing is worse than no
  # track. The guard is `#target&.positive?` — presence AND sign — because nil is now a reachable
  # answer where it used to be `nil.to_f` quietly reading as zero.
  #
  # THE FLOOR IS AT THE READER, and it is what keeps every render site from drawing a bar of negative
  # width. A claim cannot itself go below zero — `ClaimCalculator` clamps at zero per period — but
  # the clamp costs nothing and is what the two render sites (this card and the index card, through
  # this same method) are entitled to assume rather than each re-checking.
  #
  # The type is Integer at both bounds by construction — `.round` on the quotient, and two Integer
  # clamp bounds.
  def progress_percentage
    return 0 unless bar?

    (fund_figure / target * 100).round.clamp(0, 100)
  end

  # A BAR NEEDS SOMETHING TO BE A FRACTION OF — `HomePresenter::ClaimLine#bar?`'s rule, asked of the
  # category. Both render sites gate on this rather than on `#building?`, so an uncapped fund gets
  # its heading and its figure and no track — and so does a fund with a sibling rule, whose target
  # `#target` withholds (fix wave — MED-1).
  def bar? = target&.positive? || false

  # ** `#remaining_amount` IS DELETED. ** `target − claim`, floored at zero — and it was callerless
  # (grepped across `app` and `spec`): the card prints a percentage and the target itself, never the
  # gap. Under §2.1 row 2 it would have needed a nil arm of its own, and adding one to a reader
  # nothing calls is inventing an answer to a question no screen asks.

  # ---- What the card says about the rules -------------------------------------------------------

  # THE RULE RECORDS THEMSELVES, in the lines' own order, for the heading that counts them. Read off
  # `#lines` rather than through a second trip to the ledger, so "2 rules" cannot count a set the
  # list below it does not render.
  def rules = lines.map(&:rule)

  def rules? = lines.any?

  # WHEN THIS CATEGORY STARTED COUNTING (§3.2). Printed rather than alluded to, because it is the one
  # date on the card that says which of the user's spending and which of its rules' periods the
  # figure above it is made of: it is `ClaimCalculator#accrual_start`'s first term — the day the
  # accrual walk opens in — and it is the day `Entry.draining` starts attributing this category's
  # spending to its rules. Anything earlier is in neither sum.
  delegate :funded_since, to: :category

  # ---- The unfunded arm -------------------------------------------------------------------------

  # WHETHER THE BUDGET PAGE IS CURRENTLY PROPOSING A RULE FOR THIS CATEGORY. A rule is now the ONLY
  # way out of this arm — under the moved-money model an allocation was a second door, and §5 closes
  # it — so the pointer is the whole of what this card can offer.
  #
  # `SuggestionEngine` itself, never a re-derivation of the four detectors' conditions: the pointer
  # exists to say that something is waiting on /budget, and a second reader of "is there" that
  # disagreed with the panel would send the user to an empty list — or, worse, stay silent over a
  # real one.
  #
  # THE COST, AND WHY IT IS PAID ON ONE ARM ONLY. The engine is 8 queries and ~14ms warm on the
  # demo's three-year history against a page that costs 14 queries and ~76ms. A holder category
  # never runs it. Gated at the reader rather than in the view so no second caller can inherit the
  # run without the state that justifies it.
  def suggestions
    return [] unless proposable?

    # `dig(:budget, :category_id)` IS THE ENGINE'S OWN ANSWER to "which category would accepting
    # this move" (Task 5 collapsed the prefill into ONE hash, and the flat read left here answered
    # nil for every suggestion — this pointer went silent on every category in the app).
    @suggestions ||= engine_suggestions.select do |suggestion|
      suggestion.prefill.dig(:budget, :category_id) == category.id
    end
  end

  def suggested? = suggestions.any?

  # WHICH RUN ON /budget TO LAND IN. The engine's order is kind rank first (dated bills before
  # rates), so the first suggestion's kind is the most urgent thing waiting there, and
  # `suggestion_kind_anchor` is the same reader the panel's own index and headings use — one
  # spelling of the fragment, so this link cannot silently stop working.
  def first_suggestion_kind = suggestions.first&.kind

  private

  def build_line(rule)
    calculator = claims.calculator_for(rule)

    Line.new(
      rule: rule,
      shape: calculator.shape,
      claim: calculator.claim,
      spent: calculator.spent_this_period,
      accrued_this_period: calculator.accrued_this_period,
      built_up: calculator.built_up,
      target: calculator.target,
      capped: calculator.capped?,
      next_due_on: calculator.next_due_on,
      planned_this_period: calculator.planned_this_period,
      over: calculator.over?,
      over_by: calculator.over_by,
      overdue: calculator.overdue?
    )
  end

  # `Category.rule_order`, THE APP'S ONE KEY (fix wave — LOW-3): this card, the Budget page's group
  # and Home's period row list the same category's rules, and until the model owned the key Home
  # listed them differently.
  def line_order(line)
    Category.rule_order(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id)
  end

  # WHETHER A PROPOSAL COULD BE ABOUT THIS CATEGORY AT ALL — ONE CONDITION, and it stays one.
  #
  # `SuggestionEngine#unfunded_categories` is `expense_categories.reject(&:holder?)` — literally this
  # arm's own population — so the gate and the detector it gates are the same predicate rather than
  # two that can drift.
  #
  #   claims nothing → asks   (the unfunded arm's only way out)
  #   has a claim    → silent (the holding arm)
  #
  # Asked of the model rather than of #state's symbol so an edit to the state names cannot widen
  # the gate, and written as a predicate rather than `state == :unfunded` so there is one place a
  # future arm has to be argued into.
  def proposable? = !category.holder?

  def engine_suggestions = SuggestionEngine.new(user: category.user, today: today).suggestions
end
