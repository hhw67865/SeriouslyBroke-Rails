# frozen_string_literal: true

# ONE SUBMISSION FROM THE ADJUST PANEL, TURNED INTO ONE DATED ROW — or into the sentence saying why
# it cannot be one (computed-claims spec §3.3).
#
# ** WHY A FORM OBJECT AND NOT A VALIDATION ON `Adjustment` (fix round MED-1). ** The rule this
# class enforces is that a delta must be dated where the rule's own walk will COUNT it, and that is
# a fact about the DOOR a user comes through rather than about the record:
#
#   * the walk itself has to be able to read rows from any period — summing them across the whole
#     span from the accrual start is the entire subject of §3.2, and `claim_calculator_spec` plants
#     deltas in February to assert September's figure;
#   * §7's migration CONVERTS every existing purpose-side transfer into an adjustment "same date",
#     and those dates are historical by construction — a record-level refusal would reject the
#     user's own history on the way in;
#   * `ClaimLedger` and the row list read the table; nothing but this class writes to it from a
#     form.
#
# So the record keeps the two invariants that are true of every row anywhere (a non-zero amount, a
# date), and the reachability rule lives at the one place a person can type a date. There is
# exactly one such place, so this is still one spelling.
#
# THE SPAN ITSELF IS `ClaimCalculator#countable_span` AND IS NEVER RE-DERIVED HERE. It is the walk
# read as a range of days — its own first day through today, in the owner's zone — and its header
# carries why each bound is where it is.
#
# ** THE SPAN'S UPPER BOUND AND THE ROW'S OWN DAY ARE NOW THE SAME EXPRESSION (fix round 2 —
# LOW-1). ** This class asks two questions about "today" and they have to have one answer, or a
# submission left to the app can be dated on a day this class then refuses:
#
#   * the SPAN's end is the calculator's `today`, which defaults to `Budget#today` → `Category#today`
#     → `User#today` — that is `user.local_day(Time.current)`;
#   * the ROW's day is `Adjustment#local_day` of `#chosen_date`, and a blank date is `Time.current` —
#     that is `user.local_day(Time.current)` too.
#
# One re-zoning (`User#local_day`), one instant (`Time.current`), so the bound and the day are equal
# BY CONSTRUCTION rather than by luck. They agreed before this too, but only inside a request, where
# `around_action :use_user_timezone` had made the ambient `Date.current` the owner's day; from a job
# or a console the bound read UTC while the row read Tokyo, and a Tokyo user's own "today" could fall
# a day past the span that was about to judge it.
#
# ONE CALCULATOR FOR THE WHOLE SUBMISSION, because three of the four questions this class asks are
# about the same walk: what a skip is worth (§3.3), which days count, and which words the flash
# uses. A second instance would be a second walk free to disagree with the first about the period
# it is standing in.
class AdjustmentForm
  # "Sep 4" — the same day format the rule row and the delta list print, so the sentence that
  # refuses a date and the dates already on screen read as the same kind of thing.
  DAY = "%b %-d"

  attr_reader :rule, :name, :today, :calculator, :adjustment

  # `name` IS HANDED IN rather than derived: what to call a rule on screen is
  # `BudgetPageHelper#budget_rule_name` (the item it pays, else the category it fills), and a
  # second spelling here would be free to name a rule one thing in a refusal and another in the
  # flash that follows the retry.
  def initialize(rule:, params:, name:, today: rule.today)
    @rule = rule
    @params = params
    @name = name
    @today = today
    @calculator = rule.claim_calculator(today: today)

    # ** THE CALCULATOR IS READ BEFORE THE ROW IS BUILT, AND THE ORDER IS THE CONSTRAINT (fix round
    # 2, NEW-6b). ** `#amount` asks the calculator what this period has accrued, and the calculator
    # answers by mapping `rule.adjustments` — the association `.new` APPENDS the unsaved row to. So
    # the row this class builds is inside the collection the figure is summed from, and the memo has
    # to be taken while that collection is still only what the database holds. Two locals rather
    # than two arguments, so the order is a statement rather than a fact about how Ruby happens to
    # evaluate an argument list.
    #
    # MEASURED: reordering these two statements changes no answer TODAY, because a row built before
    # its amount is known carries nil and `nil.to_d` is zero. That is an accident of bigdecimal, not
    # a design — any spelling that knows the amount before the row is appended reads its own $150
    # back as $0 and writes the zero `Adjustment` refuses. `adjustment_form_spec` pins the invariant
    # and says the same thing about what the pin can and cannot catch.
    written_amount = amount
    written_date = chosen_date

    @adjustment = rule.adjustments.new(amount: written_amount, date: written_date)
  end

  def save
    return false unless acceptable?

    adjustment.save
  end

  # THE RECORD'S OWN SENTENCES AND THIS CLASS'S, through one reader — the refusals below are added
  # to `:base`, so `full_messages` prints them as written rather than prefixed with a column name.
  def error_sentence = adjustment.errors.full_messages.to_sentence

  def skip? = @params[:skip].present?

  # `#rate?` IS THE DATE QUESTION (which days a delta may land on — see `#reach_clause`) and
  # `#allowance?` IS THE VOCABULARY ONE (two-shapes §12's ruling): a fund answers NO to the first
  # and YES to the second, because it walks like a dated rule and is topped up like a rate one.
  delegate :rate?, :allowance?, to: :calculator

  private

  # THE ANSWER IS THE RECORD'S OWN ERROR LIST, so one reader (#error_sentence) prints whichever of
  # the three refusals was reached and this class needs no second place to keep a message.
  def acceptable?
    add_refusal
    adjustment.errors.empty?
  end

  # FOUR REFUSALS IN THE ORDER A USER MEETS THEM.
  #
  # THE SKIP IS CHECKED FIRST because its amount is the server's own: "Amount must be other than 0"
  # is the record's honest complaint about a figure the user never typed and could not act on.
  #
  # THE SPAN IS CHECKED LAST, AFTER `#valid?`, for two reasons — `valid?` CLEARS the error list, so
  # anything added before it would be wiped, and a date the column could not hold casts to nil,
  # which `#local_day` cannot re-zone. The record's own `presence` refusal gets there first.
  #
  # AN EMPTY SPAN GETS ITS OWN SENTENCE AND MUST BEAT `#out_of_reach` (fix round 2, NEW-4): a rule
  # whose walk has not opened counts nothing dated anywhere, so "pick a date between Sep 1 and
  # Sep 3" would be a remedy for a refusal no date can lift.
  def add_refusal
    return adjustment.errors.add(:base, nothing_to_skip_sentence) if nothing_to_skip?
    return unless adjustment.valid?

    refusal = date_refusal
    adjustment.errors.add(:base, refusal) if refusal
  end

  # THE TWO WAYS A DAY CAN FAIL TO COUNT, and nil for the one way it can. Split out from
  # `#add_refusal` so that method reads as the ORDER of the checks and this one as the date's own
  # question; between them they are the same four returns.
  def date_refusal
    return not_counting_yet if countable_span.none?
    return if countable_span.cover?(adjustment.local_day)

    out_of_reach
  end

  def nothing_to_skip_sentence = "#{name} isn't accruing anything this period, so there's nothing to skip."

  # A RULE THE WALK HAS NOT REACHED. `ClaimCalculator#countable_span` is empty exactly when
  # `#walk_periods` visited nothing — a rule asked about a day before it was written — and
  # `Range#none?` answers that in one step for either shape, because a non-empty range is truthy at
  # its first element. Unreachable from the page, whose `today` is the owner's own day and whose rules
  # cannot be created in the future; it is the honest answer to a hand-built request and to any
  # later caller that injects a `today:` of its own.
  def not_counting_yet = "#{name} hasn't started counting yet, so there's nothing to adjust."

  # A PERIOD ACCRUING NOTHING HAS NOTHING TO SKIP, and both halves of "nothing" matter: at exactly
  # zero the row would be the zero `Adjustment` refuses, and BELOW zero a −accrued is a POSITIVE
  # row — money added to the fund under a flash saying the period was skipped. `Rule#skippable?`
  # hides the button in both states and this is the backstop for a submission that arrives anyway.
  def nothing_to_skip? = skip? && !calculator.accrued_this_period.positive?

  def countable_span = @countable_span ||= calculator.countable_span

  # THE SPAN IN THE USER'S WORDS, saying both what the rule counts and what to do about it. The two
  # shapes reach back differently — §3.1's envelope is use-it-or-lose-it and carries nothing from
  # last period, §3.2's fund has been filling since it was written — so the clause names the reason
  # and the dates name the remedy.
  def out_of_reach
    "#{name} #{reach_clause} — pick a date between " \
      "#{countable_span.first.strftime(DAY)} and #{countable_span.last.strftime(DAY)}."
  end

  def reach_clause
    return "counts this period only, up to today" if rate?

    "counts dates from when it started building, up to today"
  end

  # WHAT THE ROW IS WORTH, and the three ways a submission can say it:
  #
  #   * `skip` — the server computes it, and it is −ACCRUED rather than −planned (fix round MED-2).
  #     §3.3's "skip a period = an adjustment of −planned" is stated of a bare period; the act is
  #     "accrue nothing this period", and `planned_this_period` is PRE-adjustment — so on a period
  #     already carrying a +$50 top-up, −planned leaves $50 still accruing, and on one already
  #     skipped it raids the fund's prior savings for another −$150 under a flash that says
  #     "skipped". `accrued_this_period` is `planned + Σ this period's deltas`, so −it lands the
  #     period at exactly zero, which is what the word means.
  #   * `amount_sign` — the form types a MAGNITUDE and the button pressed says the direction, which
  #     is what lets one input serve "top up" and "reduce" without asking the user to type a minus.
  #   * a bare signed `amount` — the route's own contract, which the buttons are one spelling of.
  def amount
    return -calculator.accrued_this_period if skip?
    return -@params[:amount].to_s.to_d.abs if @params[:amount_sign].to_i.negative?

    @params[:amount]
  end

  # THE DAY THE DELTA LANDS ON, IN THE OWNER'S ZONE (§3.3: it applies to the period CONTAINING its
  # date), and BOTH ARMS GET THERE THROUGH `Time.zone` — which `ApplicationController`'s
  # `around_action :use_user_timezone` has already set to the owner's.
  #
  #   * blank — `Time.current`, the owner's now. A UTC evening is already tomorrow in Tokyo, and
  #     `Date.current` here would be the same day by luck rather than by construction — see the
  #     header for why this arm and `#countable_span`'s upper bound are now one expression.
  #   * given — the string is assigned to the column and Rails' time-zone-aware attributes parse it
  #     in `Time.zone`, so "2026-09-02" is midnight in NEW YORK rather than at UTC — a difference of
  #     a whole calendar day. A `Time.zone.parse` of our own would be a second spelling of the cast
  #     that is already happening, and `adjustments_spec`'s New York example pins it either way.
  #
  # AN UNPARSEABLE VALUE CASTS TO nil AND IS REFUSED BY THE MODEL, never raised: `date` is
  # `presence`-validated, so garbage arrives as the same 422 every other bad field does — and it
  # arrives BEFORE `#countable_span` is asked to cover a day that does not exist.
  #
  # ** A SKIP IS ALWAYS TODAY, AND A DATE ON THE WIRE IS IGNORED THERE (fix round 2, NEW-3). ** Its
  # amount is −`accrued_this_period` — a figure about THIS period and no other — so a date landing
  # it in a past one would take September's accrual out of August, leaving the period the flash says
  # was skipped exactly where it was. The panel's skip posts a bare button and no date; the date is
  # the server's on that door for the same reason the amount is.
  def chosen_date
    return Time.current if skip?

    @params[:date].presence || Time.current
  end
end
