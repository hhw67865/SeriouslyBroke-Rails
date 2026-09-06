# frozen_string_literal: true

# ** THE RULE FORM'S PREVIEW CARD — THE RULE SAID BACK, OFF ONE CALCULATOR (two-shapes spec §5). **
#
# §5: "The preview says the rule back … and under it the arithmetic: per period, periods until the
# date, already built up, 'Home will show …'. It is rendered by the SERVER (a Turbo Frame refreshed
# on change, reading `ClaimCalculator` on the unsaved rule — one spelling of the per-period figure),
# so it is never a second arithmetic."
#
# ** WHY A PRESENTER AND NOT ARITHMETIC IN THE VIEW. ** Every figure on this card is a figure some
# other screen already prints about the same rule: `#standing_ask` is what the Budget page's tiles
# sum, `#periods_left` is the divisor behind the catch-up share, and the row under "Home will show"
# is `ClaimLine` — Home's own. A view computing any of them would be the second arithmetic §5
# forbids, and the one that a user comparing this card with the page it links to would catch.
#
# ** ONE CALCULATOR, MEMOISED, AND EVERY MEMBER READS IT. ** The card is re-rendered on every change
# to the form, so a second walk per render would be a walk per keystroke; more to the point, two
# calculators on one card is how the per-period figure and the row beneath it come to describe
# different money.
#
# ** THE LANES ARE EMPTY FOR A RULE THAT DOES NOT EXIST, AND REAL FOR ONE THAT DOES (this task's
# ruling). ** `ClaimCalculator` takes `spending:`/`adjustments:` as already-fetched rows, with `nil`
# meaning "run your own queries" and `[]` meaning "nothing, and I checked". A NEW rule gets `[]`:
#
#   * it has no adjustments by construction (there is no row for one to point at), and
#   * the spending it WOULD read is the category's, which makes the card an answer about this
#     afternoon's receipts when the question the form is asking is what the RULE will cost — and it
#     would cost a query on every keystroke to say it.
#
# An EDIT gets the real lanes (`nil`), because that rule's history is exactly what "already built
# up" is asking about. The consequence is stated rather than hidden: a NEW rate rule's card reads
# "$0.00 of $400.00" where Home may show spending against it the moment it is saved. The card is
# about the rule; Home is about the money.
#
# ** WHAT MAKES THE CARD SAFE TO BUILD AT ALL is `#ready?`. ** A half-filled form has no shape to
# compute — a dated rule with no date is not a rule — so the card lists the blanks instead of a
# figure, and no calculator is built. That is also why `ClaimLine` is only ever constructed here
# once the type has been chosen: the row's stripe reads `rule_type`, which is nil until it is.
class RulePreview
  attr_reader :rule_form, :user, :today

  def initialize(rule_form, user:, today: user.today)
    @rule_form = rule_form
    @user = user
    @today = today
  end

  # THE UNSAVED (or in-edit) RECORD THE WORDS HAVE ALREADY BEEN APPLIED TO — `RuleForm` assigns them
  # in its constructor, so this is the rule these words describe on every path.
  def rule = rule_form.budget

  def ready? = missing.empty?

  # ** WHAT THE CARD SAYS INSTEAD OF A FIGURE, IN THE ORDER THE STEPS ASK (§5). ** A blank is not a
  # 422: nothing has been submitted, the user is mid-sentence, and "Pick a date." is the sentence a
  # preview owes them. The refusals `RuleForm` states — a date on a per-period rule, an interval with
  # the box unticked — are not here, because with the reveals on screen they are unreachable and
  # without them the SAVE says so under the control that chose.
  # THE OWNER IS FIRST AND IT IS UNREACHABLE FROM THE PAGE, deliberately: `/budgets/new` without a
  # category redirects, and the form carries the one it opened on in a hidden field. What can still
  # arrive owner-less is a hand-made POST, which re-renders this form with `Budget`'s own 422 — and
  # a card that tried to price a rule with no owner would raise instead (`ClaimCalculator` reaches
  # the user THROUGH the category). One sentence, and the page stays legible.
  def missing
    @missing ||= [
      missing_owner, missing_amount, missing_item, missing_date, missing_interval, missing_type
    ].compact
  end

  # ONE READER PER BLANK, in the order the steps ask. Five `if`s in one array literal is the same
  # list with one method's complexity — and the sentence a user reads is easier to find beside the
  # test that produces it than inside a five-armed expression.
  def missing_owner = ("Pick the category this rule is for." if rule.category.blank?)

  def missing_amount = ("Fill in an amount." unless amount.positive?)

  # ** AN ITEM FROM SOMEWHERE ELSE IS A RULE THE SAVE WILL REFUSE, AND THE CARD MUST NOT PRICE IT
  # (fix round 1 — L2). ** `Budget#item_must_belong_to_category` states it as a 422 ("must belong to
  # this category"); the preview said nothing and quoted a per-period figure for a rule that cannot
  # be written, which is the one thing a card whose whole job is to be believed must not do. The
  # state is reachable: `#scoped_owners` admits the user's OWN item from another category (whose is
  # the controller's question, what shape is the model's), so a stale prefill or a hand-made URL
  # lands here. The predicate is the validation's own comparison, said once more rather than the
  # record asked to validate itself — `#valid?` here would run the catch-all rule's query on every
  # keystroke of a form that re-previews as it is typed into.
  def missing_item
    return nil if rule.item.blank? || rule.item.category_id == rule.category_id

    "Pick an item in #{rule.category&.name}."
  end

  def missing_date = ("Pick a date." if by_date? && rule.anchor_date.blank?)

  def missing_interval
    "Say how many months it comes round in." if rule_form.repeats? && rule.interval_months.blank?
  end

  def missing_type = ("Choose what kind of rule this is." if rule_form.rule_type.blank?)

  # THE FIGURE IN THE BOX, as a number this class can compare against zero. A decimal column casts
  # anything unparseable to 0, which is exactly the answer "Fill in an amount." is for.
  def amount = rule.amount.to_d

  def by_date? = rule_form.schedule == "by_date"

  # WHICH OF THE THREE SENTENCES §5 GIVES THE HEADLINE — and they are read off the CALCULATOR's
  # shape and the rule's own interval, never off the radio: the words have been through
  # `RuleForm`'s mapping by now and the columns are what a saved rule would carry.
  delegate :rate?, to: :line

  def repeating? = line.dated? && rule.interval_months.present?

  # ---- the arithmetic, all four off the one calculator ------------------------------------------

  # WHAT THE RULE COSTS A TYPICAL PERIOD — `ClaimCalculator#standing_ask`, the same constant
  # `Budget#steady_ask` reads and the Budget page's "Your rules need" tile sums. The card's headline
  # figure is this one, so a rule previewed at $100.00 a period joins that tile at $100.00 a period.
  delegate :standing_ask, to: :calculator

  # HOW MANY PERIODS ARE LEFT TO FILL IT, THIS ONE INCLUDED. Nil for a rate rule, which has no day
  # to count toward, and the row is simply absent there.
  delegate :periods_left, to: :calculator

  delegate :built_up, to: :calculator

  delegate :next_due_on, to: :line

  # ** THE ROW HOME WILL DRAW, BUILT THE WAY HOME BUILDS IT. ** `ClaimRows.line_for` is the one
  # assembler of a `ClaimLine`; the card renders it through `HomeHelper#when_words` and
  # `#figure_words`, which are the same two sentences Home and the Budget page print.
  def line
    @line ||= ClaimRows.line_for(rule, calculator, period_range: period_range)
  end

  # ---- the one row whose words do not describe its own columns ---------------------------------

  # ** A `monthly`-NO-ANCHOR RULE IS BEING READ BACK AS "Every period" (§5's ruling), AND THE CARD
  # SAYS BOTH UNITS. ** `RuleForm.from` reads such a row back as `per_period`, so by the time this
  # renders the RECORD says per-period and the calculator prices the figure in the box as a PERIOD's
  # money. That is what saving would do — and it is a 2.17× rise on a fortnightly grid, which the
  # user has to be able to see before they press the button. `BudgetPageHelper
  # #budget_monthly_conversion_note` says it beside the field; this says it in the card's own units.
  # ** THE ROW'S OWN MONTHLY FIGURE, WHICH IS THE ONE NUMBER THE FORM NO LONGER HOLDS. **
  # `RuleForm.from` divides on the way in (fix round 1's ruling), so the box is per-period money and
  # $260.00 a month exists nowhere on the page except on the flag that travels with the words. This
  # class does NOT re-derive it by multiplying the box back up: that would be a second normaliser
  # beside `Budget#steady_ask`, and it would move the moment the user edited the amount — the row's
  # figure is a fact about the database, not about the box.
  delegate :converted_from_monthly?, to: :rule_form

  def monthly_amount = rule_form.converted_from_monthly

  private

  def calculator = @calculator ||= rule.claim_calculator(today: today, spending: lanes, adjustments: lanes)

  # `[]` FOR A RULE THAT DOES NOT EXIST, `nil` FOR ONE THAT DOES — see this class's header. The two
  # are not interchangeable on `ClaimCalculator`: `nil` means "not batched, run your own queries".
  def lanes = rule.new_record? ? [] : nil

  def period_range = @period_range ||= ClaimRows.period_range_for(user, today)
end
