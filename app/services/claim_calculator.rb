# frozen_string_literal: true

# WHAT ONE RULE CLAIMS FROM THE USER'S MONEY (computed-claims spec §3) — the reader that replaces
# every purpose-side balance in this app.
#
# NOTHING MOVED TO PUT THE MONEY HERE. A claim is a FUNCTION of the rule, the calendar, the category's
# spending and its dated adjustments, computed at the instant it is asked for: there is no
# distribution to run, nothing to miss, and the envelope is knowable on any day including days that
# have not happened yet. `free = min(pot, total_money − Σ claims)` is the DEFINITION that replaces the
# old `available + Σ holdings == total` partition (§2), and it lives on `ClaimLedger`.
#
# THREE SHAPES, ONE CLASS, AND THE SHAPE IS READ OFF TWO COLUMNS (see #shape):
#
#   RATE (§3.1)   — "$400 a period on Groceries". Use-it-or-lose-it: `max(0, rate + Σ adjustments
#                   this period − spent this period)`, reset to the rate at every boundary, nothing
#                   carried. The rule has no anchor and its category names no target.
#   DATED (§3.2)  — "$5,000 every 2 years, next due Jun 1". Accrues toward the RULE's amount by the
#                   catch-up formula, capped there, dropped by what is spent on its lane, and re-aimed
#                   at the next occurrence once the bill is paid.
#   TARGET (§3.3) — the old savings goal: no anchor, but the CATEGORY names a figure. The same walk
#                   with no due date to spread it over, so its per-period accrual is its own rate
#                   (`Budget#steady_ask`) capped by what is still missing.
#
# ** THE WALK IS THE WHOLE OF §3.2, AND IT RUNS FROM `funded_since` EVERY TIME. ** Period by period,
# from the period containing the category's funding date through the period containing `today`:
#
#     planned(P) = (target − built_up_before_P) ÷ periods_left_from(P)      # recomputed each period
#     built_up   = clamp( min(built_up_before + planned(P) + Σ adj(P), target) − spent(P), 0, target )
#
# A PERIOD'S ACCRUAL COUNTS IN FULL THE DAY THE PERIOD OPENS (§3.2), which is why `periods_left`
# counts the current period's own boundary and why the fund is whole ON the due date rather than at
# the end of the month containing it. `BudgetCalculator#periods_until_due` counted from `today` and so
# did NOT include a boundary already passed — two answers to one question about one bill, which is
# why that class was deleted in the fix wave.
#
# TWO FIGURES COME OFF THIS WALK AND THEY ARE NOT THE SAME QUESTION. `#planned_this_period` is what
# the rule asks of THIS period — catch-up, so it moves with the fund, the spending and the calendar —
# and it is what a row and the adjust panel print. `#standing_ask` is what the rule costs a TYPICAL
# period — a constant of the rule and the grid, read by `Budget#steady_ask` and therefore by §9's
# structural verdict, which is a sentence about the SHAPE of the rules and must not move with cash.
#
# ** WHY THE SPENDING IS INSIDE THE WALK RATHER THAN SUBTRACTED AT THE END. ** §3.2 states the
# formula as `Σ accruals since funded_since − spent_since_last_fulfilment`, and read literally — the
# accrual sum over the whole span, the spending only since the last payment — a rule paid twice reads
# FULL the day after it was emptied (measured: a $600 six-monthly premium paid in June and again in
# December reports $600 built up on Dec 2). Subtracting each period's spending inside the walk is the
# same sentence with the two spans made equal, and it is what makes §3.2's other two clauses true at
# once: the built-up "drops by the amount spent" (a $200 part payment leaves $400, not zero), and the
# accrual "restarts toward the NEXT due date" because the cycle rolls on payment (#due_on) and the
# catch-up formula re-plans against the new date on the very next period.
#
# ** THE CLAMP AT ZERO IS PER PERIOD, AND THAT IS WHAT MAKES A SPILL A SPILL (§3.2). ** Overpaying a
# $600 bill by $100 must not put the user $100 further behind next cycle — the fund had $600 and never
# had $700, so the excess "spills into free" (the money left checking, so `total_money` fell) and the
# next period starts from zero. `#over?` reads the figure BEFORE that clamp, which is the one reader
# that can tell "spent it exactly" from "spent more than it had".
#
# PERIOD ARITHMETIC COMES FROM `User#period_boundaries` / `User#period_containing` AND FROM NOWHERE
# ELSE — one spelling, so a claim and the screen that renders it cannot disagree about which fortnight
# a Tuesday is in. The owner's calendar day for an entry is `CategoryLedger::ENTRY_LOCAL_DAY` in SQL
# and `User#local_day` in Ruby, which are each other's mirror.
#
# `spending:` AND `adjustments:` ARE THE SAME ROWS, ALREADY FETCHED — `HoldingCalculator`'s `terms:`
# seam in the shape this class needs. They are arrays of `[owner's calendar day, signed amount]`
# pairs, because §3.3's arithmetic groups BY PERIOD and a grouped SUM cannot answer which period a
# row is in. `nil` means "not batched, run your own queries"; an EMPTY ARRAY means "nothing, and I
# checked" — a truthiness test here would re-query on exactly the empty lanes the batching exists to
# make free. `ClaimLedger` reproduces both scopes line for line and pins itself against this class.
#
# A SNAPSHOT, MEMOISED AT FIRST READ: anything that writes entries or adjustments must build a fresh
# calculator afterwards.
class ClaimCalculator
  # HOW MANY PERIODS THE WALK WILL VISIT BEFORE IT STOPS — ten years of weekly periods, which is the
  # densest cadence this app offers. It is a stop, not a policy: `funded_since` cannot be in the
  # future (`Category#funding_start_is_not_in_the_future`) and every step moves forward by a whole
  # period, so the loop terminates on its own. What this guards is a `period_containing` that ever
  # answers a range not after its argument — a bug that would otherwise hang a page rather than fail.
  PERIOD_WALK_LIMIT = 520

  # THE WALK'S RUNNING STATE, carried from one period to the next and read out at the end. Every one
  # of the four is a fact about the same loop, so they travel together rather than as four loops.
  #
  # `raw` IS THE LAST PERIOD'S FIGURE BEFORE THE CLAMP AT ZERO — see #over? for what it is for, and
  # it is a member rather than a derivation because after the clamp the information is gone.
  Walk = Struct.new(:built_up, :raw, :planned, :paid) do
    def self.start = new(0.to_d, 0.to_d, 0.to_d, 0.to_d)
  end

  attr_reader :rule, :today

  def initialize(rule, today: rule.today, spending: nil, adjustments: nil)
    @rule = rule
    @today = today
    @spending = spending
    @adjustments = adjustments
  end

  # WHICH OF §3'S THREE FORMULAS THIS RULE TAKES, off two columns and no third.
  #
  # THE ANCHOR WINS OVER THE TARGET, and the pair is reachable: a Vacation category with a $2,400
  # target can carry both a $150-a-period rule and a $300 dated one. The dated rule accrues toward ITS
  # OWN amount by its own deadline — that is what a dated bill means — and the rate rule beside it
  # accrues toward the category's figure. Two rules, two claims, summed by `Category#claim`.
  def shape
    return :dated if rule.anchor_date.present?
    return :target if category&.target_amount.present?

    :rate
  end

  def rate? = shape == :rate

  def dated? = shape == :dated

  # WHAT THIS RULE CLAIMS RIGHT NOW. A rate rule's claim is this period's unspent rate and nothing
  # carries; an accruing rule's claim IS its built-up, because the money's whole purpose is to still
  # be there when the bill or the goal arrives.
  def claim = rate? ? rate_claim : built_up

  # WHAT THE RULE HAS ACCUMULATED (§3.2). ZERO FOR A RATE RULE, and that is the honest answer rather
  # than an evasion: use-it-or-lose-it means nothing is ever built up, and returning the claim here
  # would let a screen render "built up $250 of $400" over an envelope that carries nothing at all.
  def built_up = rate? ? 0.to_d : walk.built_up

  # THIS PERIOD'S SHARE BEFORE ANY ADJUSTMENT — the rate for a rate rule, the catch-up share for a
  # dated one, the rate capped by what is missing for a dateless target. IT MOVES: with what is
  # already built up, with what was spent, with how many periods are left. That is right for a row
  # ("$150.00 this period") and wrong for a verdict about the SHAPE of a budget — see #standing_ask.
  def planned_this_period = rate? ? rate_per_period : walk.planned

  # ** WHAT THIS RULE COSTS A TYPICAL PERIOD — A CONSTANT OF THE RULE AND THE GRID, AND THE ONLY
  # FIGURE §9's STRUCTURAL CHECK MAY BE ASKED (fix wave 2 — MED-A). ** `Budget#steady_ask` is the
  # method three screens read; this is the arm of it a ONE-TIME bill takes, and it is here because
  # the divisor is a walk over `User#period_boundaries` that this class already owns.
  #
  #     one-off  → amount ÷ (periods from the accrual-start period through the period the due date
  #                falls in), floored at one period
  #     interval → the per-cycle figure `Budget#steady_ask` computes (amount × 12 ÷ periods a year ÷
  #                interval) — unchanged, and already constant
  #     rate     → the rate itself — unchanged, and already constant
  #
  # ** IT WAS `#planned_this_period`, AND THAT MADE A STRUCTURAL VERDICT MOVE WITH THIS AFTERNOON'S
  # CASH. ** The fix wave replaced `BudgetCalculator` with §3.2's catch-up share, which is the right
  # figure for a ROW and the wrong one for "your budget doesn't fit your income": catch-up divides
  # what is STILL MISSING by the periods LEFT, so a $600 bill anchored a month ago and unpaid prices
  # at the whole $600 (`#periods_left` floors at 1), fires the verdict — and clears it the afternoon
  # the bill is PAID, with no rule changed. A sentence about the shape of the rules that a payment
  # can switch off is not a sentence about the shape of the rules.
  #
  # ** THE DUE DATE IS THE ANCHOR, NOT `#next_due_on`, AND FOR THIS SHAPE THEY ARE THE SAME DATE. **
  # A one-time bill's occurrence never rolls (`#due_on` returns the anchor whenever there is no
  # interval), so nothing here reads the walk's `paid` total and nothing here can move with a
  # receipt. The START is the accrual start's own period — the first period the walk WOULD visit —
  # rather than the period containing `today`, which is what keeps the figure the same on every day
  # of the rule's life. No spending, no adjustment and no `today` is read: this method costs no
  # query at all, which is why the readers below can call it once per rule without batching.
  #
  # ** A SETTLED ONE-OFF STILL ASKS, AND THAT IS THE RULING TAKEN (fix wave 2 — MED-A/LOW-2). **
  # `#planned_this_period` drops to zero the moment the bill is paid (`#settled?`); this does not,
  # because the standing cost of a rule the user still holds is a fact about the rule and not about
  # its last payment. The consequence is stated rather than hidden: a paid one-time bill goes on
  # counting toward `Budget.steady_need` until the user deletes the rule — and the bar on the entry
  # card, whose denominator is this sum, goes on drawing instead of vanishing the day the bill
  # clears.
  #
  # THE FLOOR AT ONE PERIOD is `#periods_left_from`'s own, and it answers two shapes at once: a bill
  # due inside the period it was created in, and a user who has declared no cadence and therefore has
  # no boundaries to count. Both get the whole amount asked of one period, which is blunt and honest.
  def standing_ask
    return rate_per_period unless one_time?

    (target / periods_to_fund).round(2)
  end

  # `accrued(P) = planned(P) + Σ adjustments dated inside P` (§3.3), verbatim.
  def accrued_this_period = planned_this_period + adjustments_within(current_period)

  def spent_this_period = spent_within(current_period)

  # DID THE SPENDING EXCEED WHAT THIS RULE HAD? Read off the figure BEFORE the clamp at zero, which
  # is the only place "spent it exactly" and "spent more than there was" differ — both leave a claim
  # of zero. It is what puts a category's bar in red (§3.1) and what names an over-fulfilment (§3.2).
  def over? = rate? ? raw_rate.negative? : walk.raw.negative?

  # ** THIS PERIOD'S ACCRUAL LESS THIS PERIOD'S SPENDING, BEFORE THE CLAMP — THE APP'S ONE SPELLING
  # OF IT (fix wave — LOW-2). ** `#claim` is `max(0, this)` for a rate rule, so once the clamp has
  # been applied the difference between "spent it exactly" and "spent $60 more than it had" is gone;
  # every reader that needs the excess needs THIS figure. It was written out twice more — in
  # `EntryImpactPresenter#pre_clamp_claim`, which adds an edited entry back to it, and in
  # `HomeHelper#claim_trouble_label`, which prints its negation as `over by $60.00` — and two
  # spellings of one subtraction is how a card and a strip come to describe the same overspend by
  # different amounts.
  #
  # PUBLIC RATHER THAN A NEW METHOD, because `#rate_claim` and `#over?` above already read it: this
  # is the same expression they have always used, with the `private` taken off it.
  def raw_rate = accrued_this_period - spent_this_period

  # HOW FAR PAST WHAT IT HAD — `#raw_rate` negated, so the strip and the row print a POSITIVE excess
  # ("over by $60.00") without either of them owning the subtraction. Meaningful only where `#over?`
  # is true; below that it is simply what is left, with the sign the other way round.
  def over_by = -raw_rate

  # THE OCCURRENCE THIS RULE IS CURRENTLY SAVING FOR, or nil where there is no deadline to save
  # toward. It ROLLS ON PAYMENT and not on the calendar — `BudgetCalculator#due_date`'s rule, kept
  # because a date that passes unpaid has not been dealt with and must go on asking.
  def next_due_on = dated? ? due_on(today, walk.paid) : nil

  # ** AN OCCURRENCE THAT IS PAST ITS DATE AND STILL UNFULFILLED (§3.2/§4's trigger). ** The cycle
  # rolls on PAYMENT rather than on the calendar (see #due_on), so `#next_due_on` names the occurrence
  # nobody has settled yet: a date in its past is therefore a date that WENT BY with the bill unpaid,
  # which is §3.2 verbatim — "an occurrence whose money was never spent stays where it was anchored
  # and the row reads overdue".
  #
  # ** IT NO LONGER READS THE FUND, AND THE HALF THAT LEFT WAS SILENCING THE ORDINARY CASE (fix round
  # 1 — MED-1). ** This was `… && built_up < target`, on the reasoning that a whole fund is waiting to
  # be PAID rather than to be saved into. But §3.2's catch-up formula floors `periods_left` at 1 for a
  # date already past, so an unpaid bill's fund fills to its target in ONE period — the whole fund IS
  # the ordinary shape of an overdue bill, not the exception. A $600 premium due Aug 15, saved in full
  # and never paid, was absent from the trouble strip on Sep 3 while its row read "next due Aug 15".
  # A bill nobody has paid is a thing the user must DO, whether or not the money for it is sitting
  # there; the fund state is what the strip's SENTENCE splits on (`home/_trouble.html.erb`) and what
  # the row's tense reads (`HomeHelper#claim_schedule`), not what the trigger gates on.
  #
  # A STRICT `<`, so a bill due TODAY is not overdue: it is a thing to do today rather than a thing
  # missed, and the row says "next due" until the day is out.
  #
  # HERE RATHER THAN ON THE TWO PRESENTERS THAT ASK, because both would have to compare against a
  # `today` of their own and this class already holds the only one that matters. It is also the one
  # place the test is stated, so Home's trouble strip and the Budget page's rule row cannot come to
  # different verdicts about one rule on one afternoon.
  def overdue? = next_due_on.present? && next_due_on < today

  # HOW MANY PERIODS ARE LEFT TO FILL THE FUND, THIS ONE INCLUDED (§3.2: the accrual counts in full
  # the day the period opens). Nil where there is no due date. Floors at 1, so an overdue bill asks
  # for the whole remainder now and a user who has declared no cadence at all gets one blunt period
  # rather than a division by zero — the floor `BudgetCalculator#periods_until_due` carried before it
  # was deleted, kept here because the division is the same one.
  def periods_left
    due = next_due_on
    due ? periods_left_from(current_period.first, due) : nil
  end

  # WHAT THIS RULE IS ACCRUING TOWARD: the BILL for a dated rule (its own amount is what has to be
  # there on the day), the CATEGORY's figure for a target rule. Zero for a rate rule, which accrues
  # toward nothing.
  def target
    @target ||= case shape
                when :dated then rule.amount.to_d
                when :target then category.target_amount.to_d
                else 0.to_d
                end
  end

  # THE FIRST DAY WHOSE SPENDING CAN MOVE THIS CLAIM — the open of the first period the walk visits.
  # `ClaimLedger` asks every rule for this before it queries, so one statement can cover a whole
  # user's lanes without pulling a history nothing will read. It costs no query of its own.
  # `periods` IS EMPTY FOR A RULE NOT YET ALIVE ON `today` (see #walk_periods), and this reader has
  # to answer anyway: `ClaimLedger` asks every rule for it before it queries. The current period's
  # open is the honest floor — nothing before it can matter to a claim of zero.
  def window_start = periods.first&.first || current_period.first

  # ** DOES THIS CLAIM COUNT SPENDING ON THIS DAY (fix wave — MED-1)? ** The predicate behind
  # `#spent_within`, exposed: the walk subtracts a period's spending as it passes through it, so the
  # days that can move this figure are exactly the days covered by a period this claim is made of.
  # One period for a rate rule (use-it-or-lose-it), the whole accrual history for the other two.
  #
  # ** IT IS NOT `#countable_span`, AND THE DIFFERENCE IS A DOUBLE SUBTRACTION. ** The entry form's
  # impact card asked that reader this question and got a different one back: the span is bounded at
  # `min(today, …)` because money MOVED on a day that has not happened is not money the rule has,
  # while spending is counted by `period.cover?(day)` with no such bound. A $50 grocery entry dated
  # Feb 10 with today at Feb 6 and the period running Feb 6–19 IS subtracted by the claim and was
  # NOT visible to the card, so the card gave nothing back and subtracted it a second time: a $300
  # rate rule read $250 where the truth was $300, and editing the entry to $60 read $190 against
  # $240. A typed adjustment's date and an entry's date are two different questions about the same
  # calendar and they need two readers.
  #
  # THE DAY IS THE OWNER'S at every caller, because `#periods` is built from `today` and `today` is.
  def counts_spending_on?(day) = periods.any? { |period| period.cover?(day) }

  # ** THE DAYS AN ADJUSTMENT CAN LAND ON AND STILL BE COUNTED (§3.3; fix round MED-1). ** It is
  # #periods read as one range of DAYS rather than as a list of periods, and it answers ONE question,
  # asked by `AdjustmentForm` (the refusal) and mirrored by the adjust panel's date field (its `min`
  # and `max`): `accrued(P) = planned(P) + Σ adjustments dated inside P` sums over the periods this
  # walk VISITS, so a row dated outside them moves no figure on any screen — written, unlisted (the
  # row lists this period's deltas) and therefore unremovable.
  #
  # ** IT IS NOT "DID THE CLAIM COUNT THIS ENTRY" AND MUST NOT BE ASKED THAT (fix wave — MED-1). **
  # The entry form's impact card read it for exactly that and subtracted a future-dated receipt
  # twice: the `min(today, …)` below is right for money a user is MOVING and wrong for spending the
  # walk has already counted, which `#counts_spending_on?` above answers.
  #
  # THE START IS #window_start, WHICH IS THE WALK'S OWN FIRST DAY and not #accrual_start itself.
  # The two differ for a rule born mid-period: §3.2's "a period's accrual counts in full the day
  # the period opens" applies to the first period like any other, so a rule born Feb 10 walks the
  # whole of February and a delta dated Feb 1 IS summed. Refusing it would be refusing a date this
  # class counts. One derivation, `#accrual_start`'s, read through the periods it produced.
  #
  # THE END IS THE EARLIER OF `today` AND THE LAST VISITED PERIOD'S CLOSE, and each half of that
  # `min` answers a different way the span could outrun the walk:
  #
  #   * `today` is the bound on a rate rule, whose one period runs past it — a delta dated the 20th
  #     of a period running to the 30th would be summed by `#adjustments_within`, but money moved on
  #     a day that has not happened is not money this claim has;
  #   * THE LAST PERIOD'S CLOSE is the bound when `PERIOD_WALK_LIMIT` TRUNCATED the walk (fix round
  #     2, NEW-2). 520 periods is ten years of weekly ones, so a fund funded in 2010 stops accruing
  #     in Dec 2019 while `today` runs on to 2026 — and a row dated 2026 would land in no period the
  #     walk visited, counting nowhere under a flash saying it counted.
  #
  # AN EMPTY WALK IS AN EMPTY SPAN (fix round 2, NEW-4), and it is read off `#periods` rather than
  # off `#window_start` for exactly that case: that reader falls back to the current period's open
  # because `ClaimLedger` must be handed SOME day to query from, and a span built on the fallback
  # would offer dates inside a period the rule was not alive for — the phantom `#walk_periods` gave
  # up inventing. `AdjustmentForm` reads the emptiness and says so in its own words.
  #
  # Both bounds are the OWNER's days, because `today` is.
  def countable_span
    return (today...today) if periods.empty?

    window_start..[today, periods.last.last].min
  end

  private

  def category = rule.category

  def user = rule.user

  # ---- §3.1, the rate rule -------------------------------------------------------------------

  def rate_claim = [raw_rate, 0.to_d].max

  # THE APP'S ONE ANSWER TO "WHAT DOES THIS RULE COST A PERIOD" — $260 a month is $120 a period under
  # a fortnightly cadence, always, because 26 periods a year is what biweekly means. A normalisation
  # of this class's own would be a second answer free to drift from the structural check's.
  #
  # ** IT NEVER REACHES `steady_ask`'s ONE-OFF BRANCH, AND SINCE THE FIX WAVE THAT IS WHAT KEEPS THE
  # CALL FINITE. ** That branch reads `#standing_ask` on a calculator of its own, so a rule that
  # asked this method AND took that branch would recurse. It cannot, twice over: `#standing_ask`
  # answers the one-off shape itself and only DELEGATES here for the other two, and only ANCHORLESS
  # rules reach here at all (a dated rule takes the catch-up formula above) while `:one_off` is by
  # definition anchored — `Budget#shape_must_be_valid` pins an anchorless rule to per-period or to a
  # 1-month interval. Two disjoint shapes, checked by the model rather than by argument.
  def rate_per_period = rule.steady_ask(user, today: today)

  # ---- §3.2/§3.3, the accrual walk -----------------------------------------------------------

  # The walk's four answers in one pass, because every one of them is a fact about the same loop and
  # running it three times would be three chances to run it differently.
  #
  def walk
    @walk ||= Walk.start.tap { |state| periods.each { |period| step(state, period) } }
  end

  # ONE PERIOD OF THE WALK. The order inside it is §3.2's own: the period opens and its whole accrual
  # lands, the adjustments dated in it apply, the total is capped at the target, and only then does
  # the period's spending come out.
  def step(state, period)
    state.planned = planned_for(period, state, due_on(period.first, state.paid))
    settle(state, accrued_in(state, period), spent_within(period))
  end

  def accrued_in(state, period)
    [state.built_up + state.planned + adjustments_within(period), target].min
  end

  def settle(state, accrued, spent)
    state.paid += spent
    state.raw = accrued - spent
    state.built_up = [state.raw, 0.to_d].max
  end

  # THE CATCH-UP FORMULA (§3.2), and the two shapes that do not take it.
  #
  # A SETTLED ONE-TIME BILL ASKS FOR NOTHING EVER AGAIN. It is the only shape that can be settled — a
  # recurring rule always has a next occurrence to fund, which was `BudgetCalculator#fulfilled?`'s own
  # narrowness — and without this gate a paid one-off would re-accrue its whole amount the period
  # after it was paid, forever, because its due date never rolls.
  #
  # A DATELESS TARGET HAS NO DEADLINE TO SPREAD ITSELF OVER, so its share is its own rate, capped by
  # what is still missing: asking for $150 when $40 would finish the goal overshoots the figure the
  # user set (`HoldingCalculator#goal_required`'s rule, kept).
  def planned_for(period, state, due)
    return 0.to_d if settled?(state.paid)

    gap = target - state.built_up
    return 0.to_d unless gap.positive?
    return [rate_per_period, gap].min if due.nil?

    [(gap / periods_left_from(period.first, due)).round(2), gap].min
  end

  def settled?(paid) = one_time? && paid >= target

  def one_time? = anchor.present? && rule.interval_months.nil?

  def anchor = rule.anchor_date

  # WHICH OCCURRENCE IS BEING SAVED FOR ON A GIVEN DAY, GIVEN WHAT HAS BEEN PAID INTO IT.
  # `BudgetCalculator#due_date`'s headline rule — "the cycle rolls when the bill is PAID, not when
  # the date passes" — re-derived against the walk's own running total instead of against a per-call
  # `SUM` over the item's entries, asked once per period rather than once per query, which is what
  # lets the whole walk cost no statements at all.
  #
  # ** IT DIVERGED FROM THAT CLASS ON THE ITEM-LESS RULE, DELIBERATELY, AND THIS READING IS NOW THE
  # ONLY ONE (review of 2026-09-03; `BudgetCalculator` was deleted in the fix wave). ** That class had no
  # fulfilment signal for a rule with no item, so it falls back to "assume every bill was paid on
  # time" and rolls the due date on the CALENDAR: a $600 six-monthly rule anchored Jun 1 with nothing
  # ever spent reported Dec 1 there and Jun 1 here. The computed model has a signal it did not have —
  # an item-less rule's fulfilment is spending on the CATEGORY (§3.2), which this walk already sums —
  # so "unpaid" is a fact rather than an absence, and a date that passed with the money never spent
  # is exactly the state the user needs told. The claim stays at the target and the row reads overdue
  # instead of silently re-aiming at an occurrence six months out.
  #
  # THE `min` KEEPS A PREPAYMENT FROM ROLLING A CYCLE THAT HAS NOT COME DUE, erring in the same
  # conservative direction as #elapsed_cycles itself.
  def due_on(date, paid)
    return nil if anchor.blank?
    return anchor if rule.interval_months.nil? || !target.positive?

    anchor + (cycles_paid_by(date, paid) * rule.interval_months).months
  end

  def cycles_paid_by(date, paid) = [(paid / target).floor, elapsed_cycles(date)].min

  # How many occurrences have already come due by `date`, regardless of what was recorded. Once the
  # anchor is reached one occurrence has passed, so this is (whole intervals elapsed) + 1.
  def elapsed_cycles(date)
    return 0 if date < anchor

    (months_since_anchor(date) / rule.interval_months) + 1
  end

  # Whole calendar months from the anchor, backing off one when the day of the month has not yet been
  # reached — Dec 1 is not yet a full six months past a Jun 15 anchor.
  def months_since_anchor(date)
    months = ((date.year * 12) + date.month) - ((anchor.year * 12) + anchor.month)
    date.day < anchor.day ? months - 1 : months
  end

  # ---- the calendar --------------------------------------------------------------------------

  # THE PERIODS THIS CLAIM IS MADE OF. One for a rate rule — nothing before this period can move a
  # use-it-or-lose-it figure — and the whole span from the accrual start for the other two shapes.
  def periods
    @periods ||= rate? ? [current_period] : walk_periods
  end

  def current_period = @current_period ||= user.period_containing(today)

  # ** AN EMPTY WALK IS AN ANSWER (review of 2026-09-03). ** This used to fall back to
  # `[current_period]` when the loop visited nothing, and that fallback was a phantom: the only way
  # to visit nothing is an accrual start AFTER `today` — a rule asked about a day before it was
  # written, which is what every backdated `today:` on a fresh rule is — and inventing the current
  # period there accrues a period the rule was not alive for. Zero is the honest built-up for a rule
  # that did not yet exist. `#window_start` carries the nil arm this leaves it.
  def walk_periods
    visited = []
    cursor = user.period_containing(accrual_start)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = user.period_containing(cursor.last + 1)
    end
    visited
  end

  # ACCRUAL STARTS WHEN THE CATEGORY STARTED HOLDING MONEY, AND NEVER BEFORE THE RULE ITSELF EXISTED
  # (§3.2: "never retroactively"; Henry's ruling of 2026-09-03).
  #
  # ** THE LATER OF THE TWO, AND THE SECOND ARM IS THE RULING. ** `funded_since` is stamped by a
  # category's FIRST rule (`Category#start_holding`), so for that rule the two dates coincide and
  # nothing changes. For every rule added afterwards they do not: a $500 target rule written today on
  # a category funded two years ago would otherwise walk two years of periods and report itself
  # already built up the moment it was saved — money the user never set aside, shown as money they
  # have. A rule cannot accrue before it existed, which is the same sentence "never retroactively"
  # says about the category, asked of the rule.
  #
  # THE DAY IS THE OWNER'S, through `User#local_day`: `budgets.created_at` is an instant, and a rule
  # a Tokyo user writes on the evening of the 1st is stored on the 31st in UTC — which on a monthly
  # grid is a different period and therefore a different first accrual.
  #
  # ** A RULE BORN MID-PERIOD ACCRUES THAT WHOLE PERIOD, and the choice is deliberate (review of
  # 2026-09-03). ** The start date only decides WHICH period the walk opens in; §3.2's "a period's
  # accrual counts in FULL the day the period opens" then applies to that period like any other, so a
  # rule written on the 31st of a calendar month holds the whole month's share, not a day of it.
  # Pro-rating it would be a second, finer clock beside the period grid — the app has one — and it
  # would make the figure a user sees depend on the hour they clicked Save.
  #
  # NIL ON EITHER ARM IS SIMPLY ABSENT, not zero: an unsaved rule has no `created_at` to be born on,
  # and a category with no funding date holds nothing at all — its spending drains available — so
  # with neither there is no history to walk and the current period is the whole of it.
  def accrual_start = [category&.funded_since, rule_born_on].compact.max || today

  def rule_born_on
    return nil if rule.created_at.blank?

    user ? user.local_day(rule.created_at) : rule.created_at.to_date
  end

  def periods_left_from(from, due)
    [user.period_boundaries(from: from, to: due).count, 1].max
  end

  # THE DIVISOR BEHIND `#standing_ask`'s ONE-OFF ARM: how many periods this rule has, from the first
  # one it accrues in through the one its bill falls due in. The same count `#periods_left` makes and
  # from the same method — the difference is where it starts. `#periods_left` starts at TODAY's
  # period, because it is answering "how long have I got"; this starts at the accrual start's period,
  # because it is answering "what was this rule ever going to cost a period", and only the second
  # question has an answer that stays put.
  #
  # AN ANCHOR ALREADY PAST WHEN THE RULE WAS WRITTEN yields no boundaries at all (`to < from`), which
  # the floor turns into one period and the whole amount. That is the same answer the walk gives such
  # a rule on its first day and every day after.
  def periods_to_fund = periods_left_from(user.period_containing(accrual_start).first, anchor)

  # ---- the rows ------------------------------------------------------------------------------

  def spent_within(period) = total_within(spending_rows, period)

  def adjustments_within(period) = total_within(adjustment_rows, period)

  def total_within(rows, period)
    rows.sum(0.to_d) { |day, amount| period.cover?(day) ? amount : 0.to_d }
  end

  # `nil?` AND NOT TRUTHINESS: an empty array is a ledger saying "nothing, and I checked", and
  # falling back to a query on it would cost a statement per empty lane — which is most lanes.
  def spending_rows
    @spending_rows ||= @spending.nil? ? query_spending : @spending
  end

  def adjustment_rows
    @adjustment_rows ||= @adjustments.nil? ? query_adjustments : @adjustments
  end

  # THE LANE A FULFILMENT ARRIVES ON (§3.1/§3.2): the rule's own item where it names one, and
  # everything else in the category where it does not. `Entry.draining` is
  # `CategoryLedger::ENTRY_CATEGORY_ID` narrowed to one category — the funded-since gate and the
  # owner's calendar day included — so spending from before the category held money is absent here
  # exactly as it is absent from every other reader.
  #
  # ** `Entry.on_unruled_items` IS THE PARTITION (ruling of 2026-09-03), AND IT IS NOT A REFINEMENT
  # OF THE CATCH-ALL LANE — IT IS WHAT MAKES THE LANES ADD UP. ** Without it the catch-all's lane
  # CONTAINS the item-backed rules' lanes, so one payment lowers two claims: Σ claims falls twice
  # while the user's money falls once, and `free` RISES when a bill is paid. The scope's own header
  # carries the measurement; what matters here is that this reader and `ClaimLedger`'s grouped
  # statement compose the same scope rather than each stating the rule.
  #
  # ONE DAY OF SLACK ON THE WINDOW, because the bound is a UTC instant and the day it is protecting is
  # the OWNER's: no timezone on earth is more than 14 hours from UTC, so a day is enough to keep an
  # entry that belongs in the first period from being filtered out before it can be re-zoned.
  def query_spending
    scope = Entry.expenses.merge(Entry.draining(category))
    scope = if rule.item_id.present?
              scope.where(item_id: rule.item_id)
            else
              scope.merge(Entry.on_unruled_items)
            end
    scope
      .where(entries: { date: (window_start - 1).beginning_of_day.. })
      .pluck(CategoryLedger::ENTRY_LOCAL_DAY, :amount)
  end

  def query_adjustments
    rule.adjustments.map { |adjustment| [adjustment.local_day, adjustment.amount.to_d] }
  end
end
