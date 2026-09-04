# frozen_string_literal: true

# THE §6 IMPACT CARD — the *can I afford this* answer, at the moment it is wanted.
#
# The entry form keeps its exact shape (category → item → amount, the numpad); this is the only
# thing budgeting adds to it. The card sits under the amount field on new AND edit and shows what
# the spec's mockup shows and nothing else:
#
#     Groceries envelope
#     $240  →  $185 left                     until Feb 19
#     ▓▓▓▓▓▓░░░░░░
#
# ** EVERY FIGURE HERE IS A CLAIM NOW, AND NOT A HOLDING (computed-claims spec §3). ** Nothing is
# moved into a category any more (§5), so there is no balance sitting anywhere to read: a category's
# money is the SUM OF ITS RULES' CLAIMS, computed from the rules, the calendar, its spending and its
# dated adjustments at the instant it is asked for. `Category#claim` is that sum and it is the one
# door this class reads it through.
#
# PLAN DECISION 1 — THIS CLASS COMPUTES NO NEW FIGURE. Every number below is an existing reader:
#
#   * the balance is `Category#claim` (the app's one unbatched answer to "what does this category
#     have"), corrected on EDIT by what this entry has already taken out of it — see #balance, which
#     is the only arithmetic in this file and carries its own ruling,
#   * the bar's denominator is `Σ Budget#steady_ask` over the category's own rules — steady_ask is
#     THE per-period normaliser on this branch and a local division would be a second one, which
#     is the mixed-unit trap that has struck five times here,
#   * the date is the edge `User#period_boundaries` puts after today, taken through
#     `User#period_containing` so the window arithmetic is not spelled twice.
#
# AND IT SPEAKS NO STATUS. The card renders figures, a bar and a date. There is no "behind", no "on
# track", no colour band standing in for one — and no RULE date either: the one date it prints is
# the period's own closing edge (#period_ends_on), never an occurrence's due date, so nothing here
# reads a schedule at all. The one colour it does use is the ordinary negative-money red the account
# header already uses for a negative balance — a fact about a sign, not a verdict about a category.
#
# PLAN DECISION 2 — OVERDRAWING WARNS AND NEVER BLOCKS, and a category no rule claims is told the
# truth rather than shown an envelope that does not exist. See #unbudgeted? and #overdrawn?.
#
# NOTHING IS MOVED BY LOOKING AT IT: `free = min(pot, total_money − Σ claims)` is a DEFINITION (§2)
# rather than a partition anything writes, and this class has no writes at all. Every figure it
# prints is read.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §6 and
# docs/superpowers/specs/2026-09-03-computed-claims-design.md §§3, 5
class EntryImpactPresenter
  # WHAT COUNTS AS A TYPED AMOUNT, and it is deliberately strict.
  #
  # The amount field accepts a FORMULA (`10*5`, `192.92-85.02`) which `EntriesController
  # #evaluate_formula` hands to Dentaku on save. The browser has no Dentaku, and `parseFloat("10*5")`
  # is 10 — a figure that is WRONG rather than absent, which is the worse of the two failures on a
  # card whose whole job is to be believed. So anything that is not a plain non-negative decimal
  # reads as "nothing typed yet" and the card holds at the balance until the formula resolves into
  # one. The client-side test is the same expression (see impact_controller.js), which is what keeps
  # the two halves from disagreeing about what a number is.
  #
  # NEGATIVES ARE EXCLUDED BY THE PATTERN rather than clamped after it: `Entry` validates
  # `amount > 0`, so a leading minus is not an entry anyone can save, and reading "-10" as a $10
  # REFUND would show an envelope growing as the user types a figure the form is about to refuse.
  # A thousands separator is excluded for the same reason — "1,500" is not a number this app ever
  # writes, and guessing at it would be guessing.
  TYPED_AMOUNT = /\A\d*\.?\d+\z/

  attr_reader :user, :category, :entry, :today

  def initialize(user:, category:, amount: nil, entry: nil, today: user.today)
    @user = user
    @category = category
    @raw_amount = amount
    @entry = entry
    @today = today
  end

  # WHETHER THERE IS A CARD AT ALL.
  #
  # No category chosen yet — the opening state of a new entry — has nothing to say, and an INCOME
  # category is left deliberately silent. Income does not come out of an envelope: it lands in the
  # account, and the account is the buffer (§7.1), so the only true sentence the card could print
  # about a paycheck introduces the account/buffer relationship — a concept §6 deliberately leaves
  # out of the daily screen ("entry stays single-purpose", principle 1). The distribution screen is
  # where income meets envelopes, and it is one click away. Silence here is the spec's choice, not
  # an omission.
  def render? = category.present? && !category.income?

  # WHAT HOLDS THIS SPENDING, DERIVED AND NEVER PICKED (§6): the user chooses a category, and under
  # the two-ledger model the category IS the thing that holds the money (spec §3) — so there is
  # nothing left to derive except WHETHER it holds it.
  #
  # `Category#counts_spending_on?` — the app's ONE Ruby mirror of `CategoryLedger::ENTRY_CATEGORY_ID`
  # (§4's re-anchored start-date rule, compared in the OWNER's calendar day). It answers `holder? &&
  # local_day(date) >= funded_since`, so a category that has never been funded, and a funded one
  # asked about a day before it started holding, both answer nil here: no rule's claim can be moved
  # by that receipt, so it comes straight out of FREE money (§2) and the honest card below says so.
  #
  # ON THE DAY THE ENTRY IS ABOUT, which is what the start-date rule made this card have to say. On
  # EDIT that day is the entry's own; on NEW there is no entry and the day is `today`, the same clock
  # every other figure on this card is read at. Get it wrong and the card names a category, prints
  # its holding and offers a "left" figure for money that is never going to come out of it — the one
  # failure this card cannot have, because the whole of it is a promise about where the money the
  # user is typing will land.
  #
  # IT WAS `#pool`, AND `Category#effective_pool` WAS THE READER. That method resolved which POOL a
  # category's spending reached, with the same date gate on the envelope's `start_date`; the pool
  # layer is being deleted (§5) and the date now lives on the category itself, so the whole
  # resolution collapses to this predicate.
  # `defined?` rather than `||=`: nil is a real answer — the honest card's whole population — and a
  # truthiness memo would re-ask the predicate on every one of the six readers below that consult it.
  def holding
    return @holding if defined?(@holding)

    @holding = category.present? && category.counts_spending_on?(entry&.date || today) ? category : nil
  end

  # THE HONEST CARD (decision 2). TWO WAYS IN, and both say the same thing: no rule's claim can be
  # moved by this receipt, so the spending comes straight out of FREE money — `total − Σ claims`,
  # the money no rule has spoken for (§2).
  #
  #   * the DATE arm — `#holding` is nil, so either the category has never been funded or this
  #     receipt predates the day it started counting spending (`Category#counts_spending_on?`);
  #   * the RULE arm — `Category#budgeted?`: the category carries no rule at all, so it claims
  #     nothing however much has been spent against it (§3.4).
  #
  # ** THE RULE ARM IS FIX ROUND 1's M2 AND IT CLOSED A TWO-SCREEN DISAGREEMENT. ** This read
  # `holding.nil?` alone, and `#holding` is the category whenever it `counts_spending_on?` the
  # entry's day — a test that USED to imply the category could be holding money and stopped implying
  # it the moment claims were computed. A funded category with no rules therefore got `claim` $0.00,
  # a `balance_after` of `−amount`, `#overdrawn?` true and the danger-red overdraw notice, while
  # Home's "This period" called the very same category unbudgeted and printed `spent $X` with no
  # bar. `Category#budgeted?` is now the ONE spelling both screens ask (see its comment).
  #
  # THE TWO SHAPES IT USED TO BE were "no pool at all" and "a pool that IS an account", and they
  # were one sentence because nothing reserved money sitting in an account. That pair was
  # `Category#buffer_funded?`; its successor is `Category#holder?`, asked with a date because a
  # funded category's claim still cannot be moved by spending that predates its funding.
  #
  # The register is the Budget page's own — its rate suggestion offers a rule to exactly this
  # population — so a user who meets the sentence here and the offer there is reading one app.
  def unbudgeted? = holding.nil? || !holding.budgeted?

  # ** A CATEGORY WHOSE MONEY BUILDS UP IS A FUND, so the card takes the fund shape (`$X → $Y of
  # $Z`) rather than the envelope's (`$X → $Y left`). **
  #
  # ** IT IS THE RULE THAT SAYS SO NOW (rules-own-the-budget spec §5/§7). ** This asked
  # `Category#saving_toward_a_target?` — `holder? && categories.target_amount.present?` — and that
  # column is one no claim formula has read since the shapes moved onto the rule:
  # `ClaimCalculator#shape` answers `:building` off `carries_over` and caps at the RULE's
  # `target_amount`. Reading the category's figure here would draw a bar against a number nothing
  # computes, and — because `#denominator` is that figure — it would have gone on doing so after
  # Task 4 drops the column.
  #
  # `Category#building_rule` IS THE ONE READER, asked of the CATEGORY this card is drawing: it is
  # the item-less rule, the category's own lane, so a fund carved out for one item does not make the
  # whole category a fund. The categories index card and the categories page's holdings card ask the
  # same rule, so a fund is a fund on all three.
  #
  # ** IT IS TWO QUESTIONS WHERE `#goal?` WAS ONE, because a building rule may name NO figure (§2.1
  # row 2). ** `#building?` decides the NOUN and the card's shape; `#building_target` decides the
  # trailing phrase and the bar's denominator, and it is nil for an uncapped fund — which falls back
  # to `#steady_claim`, the ordinary envelope denominator, because what an uncapped fund adds per
  # period is the only thing there is to measure a period's spending against.
  #
  # Spending from a fund is still spending against a fund, which is why this arm exists at all: the
  # figures are the same two figures, and only the trailing phrase differs.
  def building? = holding.present? && holding.building_rule.present?

  # ** THE TARGET IS PRINTED ONLY WHERE IT IS A CEILING ON THE FIGURE BESIDE IT (fix round 1 —
  # MED-4). ** `#balance` is the WHOLE CATEGORY's claim — Σ over every rule on it — and that is not
  # negotiable: §3.1's lane ruling forbids this card from resolving which rule an entry drains,
  # because doing so means spelling `Entry.on_unruled_items`' partition a second time, in Ruby. So
  # the figure on the left is the category's, and the phrase after it has to be true OF THE
  # CATEGORY'S FIGURE or it is not true at all.
  #
  # ** MEASURED ON THE MIXED SHAPE, WHICH IS ORDINARY RATHER THAN EXOTIC. ** A "Car" category with a
  # $600-a-period fund building toward $2,400 and a $600 insurance bill on one of its items claims
  # `600 + 600` = $1,200 after one period. Printed against the fund's ceiling that reads
  # `$1,200.00 of $2,400.00` — half full — when the FUND is a quarter full and the other $600 is a
  # bill's accrual that has nothing to do with the target. The bar said the same thing twice as
  # loudly.
  #
  # SO THE TARGET ARM REQUIRES THE BUILDING RULE TO BE THE CATEGORY'S ONLY RULE, which is exactly
  # when `Σ claims` IS the fund's built-up and the target IS its ceiling. Everywhere else the card
  # falls to the sentence it already had for a fund with no ceiling — `built up`, with the ordinary
  # `Σ standing_ask` denominator — and that sentence stays TRUE on the mixed shape: both rules'
  # contributions are money the category has accrued. What is dropped is only the false "of".
  #
  # THE NOUN IS UNAFFECTED. `#building?` is a question about the SHAPE — money here builds up — and a
  # sibling bill does not make that less so.
  #
  # `budgets.load.one?` and not a `count`: the association is already loaded on every path that
  # reaches here (`Category#budgeted?` loads it, and `#claim_calculators` reads it), so this costs
  # no statement.
  def building_target
    rule = holding&.building_rule
    return nil unless rule && holding.budgets.load.one?

    rule.target_amount&.to_d
  end

  # "envelope" or "fund" — the noun the header uses.
  #
  # ** "GOAL" IS RETIRED (§7). ** A goal was a kind of CATEGORY; what this names is what the rule
  # does with money the period did not spend. "Fund" is true of the capped shape and the uncapped
  # one alike, where "goal" was true of neither without a figure to be a goal toward.
  #
  # `Pool#noun` IS GONE with the type it read: a pool had three types and a word for each, and a
  # category has one type and a question. "envelope" is the right word for a category that holds its
  # own spending money, and it is also the fallback the honest card's own headline is written in.
  def noun = building? ? "fund" : "envelope"

  # WHAT THE CATEGORY CLAIMS, AS IF THIS ENTRY WERE BEING DECIDED NOW.
  #
  # `Category#claim` and then ONE correction, which is the whole of the edit case: on edit the
  # claim has ALREADY counted this entry's spending, so a card built straight off it would answer
  # "what is left after the spending you already logged" while the user is looking at a form that
  # asks "how much is this". Typing the same figure again would appear to spend it twice. What this
  # entry has already taken out of the claim is given back, so the two figures the card prints are
  # the world without this entry and the world with it — which is the question the screen is asking.
  #
  # ** THE CORRECTION KEPT ITS SHAPE AND LOST ITS INNOCENCE (computed-claims §3.1/§3.2). ** Under the
  # old model a holding was a signed sum and adding an entry's amount back to it was exactly
  # invertible. A claim is not: `claim = max(0, rate + adjustments − spent)` for a rate rule, and an
  # accruing rule's built-up is clamped into `0..target` in every period of its walk. A CLAMP IS NOT
  # INVERTIBLE, so adding an amount back to a CLAMPED figure invents money. Measured, on a
  # $300-a-period rate rule with $400 of spending in the period of which THIS entry is $100:
  #
  #     claim                 = max(0, 300 − 400)     = $0
  #     naive give-back       = 0 + 100               = $100     ← money that is not there
  #     the truth without it  = max(0, 300 − 300)     = $0
  #
  # ** SO THE GIVE-BACK IS APPLIED BEFORE THE CLAMP AND THE CLAMP IS RE-APPLIED AFTER IT. **
  # `#pre_clamp_claim` is the same sum `Category#claim` makes, read one step earlier — a rate rule's
  # `accrued − spent` instead of `max(0, accrued − spent)` — so the arithmetic above comes out at
  # `max(0, −100 + 100)` = $0, which is the truth, and the ordinary case is untouched because the two
  # figures are the same number wherever nothing is clamped. It is what keeps the reachable shape
  # right: editing the $300 entry that overdrew a $300 envelope already carrying $60 of other
  # spending reads `max(0, −60 + 300)` = **$240 → −$60**, which is what the envelope had and what
  # this entry does to it. Adding back after the clamp would have said `$0 → −$300`.
  #
  # THREE GATES STAND IN FRONT OF IT, and none of them fires on the ordinary path:
  #
  #   1. THE ENTRY MUST DRAIN THIS CATEGORY, ON ITS OWN DATE — `#counted_by_holding?`, unchanged.
  #      Re-categorising must not credit the new category with money it never had.
  #   2. THE CLAIM MUST ACTUALLY COUNT THAT DAY — `#counted_by_the_claim?`'s first half. A rate
  #      claim is use-it-or-lose-it and sees ONE period (§3.1), so an entry from LAST period is not
  #      in the figure at all and giving it back would be pure invention: a $300 envelope with $60
  #      spent would read $285 while editing a $45 receipt from a fortnight ago.
  #      `ClaimCalculator#counts_spending_on?` is the calculator's own answer to which days its walk
  #      SUBTRACTS SPENDING ON, so the test is the walk's rather than a second reading of the
  #      calendar here. It is not `#countable_span`, which answers where a typed ADJUSTMENT may be
  #      dated and is bounded at `min(today, …)` — see #counted_by_the_claim? for the double
  #      subtraction that difference produced (fix wave — MED-1).
  #   3. NO ACCRUING RULE MAY BE SPENT PAST WHAT IT HAD — `#counted_by_the_claim?`'s second half.
  #      The pre-clamp reading above is available for a RATE rule (`accrued_this_period` and
  #      `spent_this_period` are both public) and NOT for an accruing one: §3.2 clamps the built-up
  #      inside every period of the walk, and the figure before that clamp is gone by the time the
  #      walk returns. `#over?` is the calculator's own reader for having gone past it, and where it
  #      is true of an accruing rule the card gives back NONE of the entry and shows the fund at zero
  #      going further under. That UNDERSTATES, deliberately: on a card answering "can I afford
  #      this", understating a fund already spent past zero is the safe direction and overstating it
  #      is the unsafe one.
  #
  # ALL THREE ARE ASKED OF EVERY RULE ON THE CATEGORY rather than of the one whose lane this entry
  # is on, and the alternative lost on §3.1's own ground: resolving the lane means spelling
  # `Entry.on_unruled_items`' partition a second time, in Ruby, and a second spelling of the
  # partition is exactly what that ruling forbids. What it costs is a category mixing an OVERSPENT
  # accruing rule with a healthy one, where the give-back is silenced on both lanes — an understating
  # card in a shape few categories have, against an inventing card in the shape every overspent
  # envelope has.
  #
  # AND A CEILING OVER THE LOT (#most_it_could_claim), for the clamp at the OTHER end: an accruing
  # rule's built-up is capped at its target, so giving an old fulfilment back to a fund that has
  # since refilled would print `$750.00 of $600.00`. Nothing a category claims can exceed what
  # its rules could hold at most, so the corrected figure is capped there too.
  def balance
    @balance ||= begin
      given_back = -own_contribution
      given_back.zero? ? claim : (pre_clamp_claim + given_back).clamp(0.to_d, most_it_could_claim)
    end
  end

  # The figure the amount box currently holds, as money. See TYPED_AMOUNT for what "currently holds"
  # is allowed to mean.
  def amount
    @amount ||= case @raw_amount
                when nil then 0.to_d
                when Numeric, BigDecimal then [@raw_amount.to_d, 0.to_d].max
                else @raw_amount.to_s.strip.match?(TYPED_AMOUNT) ? @raw_amount.to_s.to_d : 0.to_d
                end
  end

  # SPENDING ALWAYS SUBTRACTS (plan 3, task 5). This read `balance + amount * #direction`, where
  # `#direction` was `+1` for a savings category and `-1` otherwise, because a contribution used to
  # RAISE the pool it filled. Contributions are gone and there is no savings category to sign: every
  # card this class renders describes an expense (income is silent — see `#render?`), and an expense
  # is what §3 subtracts from a claim. The FUND arm is unaffected and still renders — spending from
  # a fund is spending against a fund, which is `#building?`'s own note.
  #
  # UNCLAMPED, AND THAT IS THE POINT OF THE RIGHT-HAND FIGURE. §3 clamps a claim at zero and this
  # subtraction does not, because "what this spending leaves" and "what the rules will claim
  # afterwards" are different questions: the claim afterwards is zero, and the figure the user needs
  # is how far past zero they are going. It is `ClaimCalculator#over?`'s pre-clamp reading, said on a
  # card — and it is why `#overdrawn?` below can be true at all.
  def balance_after = @balance_after ||= (balance - amount).to_d

  # WHETHER THERE ARE FIGURES TO PRINT AT ALL — the envelope and fund cards have them, the honest
  # nothing-claims-this card has none. Every money reader below is gated on it, because a receipt no
  # rule's claim can move has no "left" figure to offer: it comes out of free money and that is the
  # whole of what the card can say about it.
  def figures? = render? && !unbudgeted?

  # NEGATIVE IS THE ONLY TEST, and it is a fact about a sign rather than a status. Exactly zero is
  # not overdrawn: spending an envelope to the penny is the tidiest possible outcome and reading it
  # as trouble would be the same lie as `-$0.00`. FALSE with no envelope, and not an error: the
  # submit button asks this on every render of the form, including the ones with no card at all, and
  # spending that nothing reserves cannot overdraw anything.
  def overdrawn? = figures? && balance_after.negative?

  # THE BAR'S DENOMINATOR — what this category is FOR, per period.
  #
  # `Σ Budget#steady_ask` over the category's own rules: steady_ask is the one per-period normaliser on
  # this branch (a $1,500-a-month rule claims $692.31 of a biweekly period, and a bar denominated in
  # sticker prices would draw a full envelope as a fifth of one).
  #
  # A CAPPED FUND MEASURES AGAINST ITS TARGET INSTEAD, and this is a CORRECTION to the plan's
  # wording ("the bar's denominator is Σ steady_ask") rather than an exception to its ruling — the
  # ruling is that the card invents no normaliser, and the fund's target is an existing reader that
  # this bar and the categories page's bar already measure against. Measured on the demo seeds, both
  # halves:
  #
  #   * Retirement Supplement claims $545 against a $100,000 target and $150 a period of rules.
  #     Under the steady_ask denominator its bar is drawn FULL while the line directly above it
  #     reads "of $100,000.00" — two answers to one question, an inch apart, on the same card.
  #   * The other four funds (Emergency Fund, House Down Payment, New Car, Vacation to Europe)
  #     carry only hand-fed rules, so Σ steady_ask is zero and their bars could never move — empty
  #     on a fund the user is watching fill. Such a fund claims nothing at the start either, so the
  #     bar is empty for a second and better reason; the target denominator is what lets it start
  #     moving the moment money is set aside.
  #
  # ** AN UNCAPPED FUND FALLS BACK TO Σ steady_ask (rules-own-the-budget spec §2.1 row 2). **
  # `#building_target` is nil for it — there is no ceiling — and the honest denominator for a card
  # asking "can I afford this" is then the same one an envelope gets: what the category's rules ask
  # of a period. It is not the target arm wearing a different figure; it is the absence of a target,
  # and the fallback is what the `||` has always meant.
  #
  # The rate case is untouched: a budgeted category's bar is Σ steady_ask, exactly as ruled.
  def denominator = @denominator ||= building_target || steady_claim

  # WHETHER THERE IS A BAR AT ALL. An envelope with no rules on it has no per-period claim, so
  # there is nothing for a bar to be a fraction OF — and an empty track drawn beside real figures
  # says "nothing left" an inch under a line saying $240.00, which is the same two-answers-on-one-
  # card defect that moved the fund's denominator. No denominator, no bar.
  #
  # ** A CATEGORY WHOSE ONLY RULE IS A SETTLED ONE-TIME BILL DRAWS A BAR AGAIN (fix wave 2 — LOW-2).
  # ** For one wave `#steady_claim` read §3.2's catch-up share, which is ZERO once a one-off has been
  # paid — so the bar under an envelope that had one all along simply stopped being rendered the
  # afternoon the bill cleared. `#standing_ask` is what the rule costs a period whatever its payment
  # history, so the denominator is positive for as long as the rule exists and the track goes on
  # being drawn.
  def bar? = figures? && denominator.positive?

  # BALANCE-AFTER OVER THE DENOMINATOR, CLAMPED 0..1. Zero when there is nothing to measure against:
  # the bar is not rendered in that case (see #bar?), and the guard stays because dividing by it
  # would be a `ZeroDivisionError` on a rendering path and this reader is public.
  def bar_fraction
    return 0.to_d unless denominator.positive?

    (balance_after / denominator).clamp(0.to_d, 1.to_d)
  end

  def bar_percent = (bar_fraction * 100).round

  # THE DAY THE PERIOD RUNS TO, or nil for a user who has declared none.
  #
  # `User#period_containing(today).last` is the next boundary minus a day — the same window
  # arithmetic every other screen uses, taken from the one method that owns it. GATED ON THE
  # DECLARATION rather than taken on trust: `period_containing` falls back to the calendar month
  # for an undeclared user, which is the right fallback for a normaliser and a lie on a card, since
  # "until Aug 31" would state a period boundary the user never set.
  #
  # TODAY'S PERIOD, NOT THE ENTRY'S DATE FIELD. The card answers "what is in this envelope and what
  # will be left" — a fact about now — while the date field records when the receipt is from. A
  # back-dated coffee does not move the envelope's period end, and reading the date field here would
  # have the card's right-hand figure jump around as a user corrects a date.
  def period_ends_on
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today).last
  end

  # THE TWO FIGURES THE BROWSER RE-READS while the user types, as digits `parseFloat` can hold. See
  # `DigitsHelper.digits` for why the delimiter is the defect.
  def balance_param = DigitsHelper.digits(balance)

  def denominator_param = DigitsHelper.digits(denominator)

  private

  # `Σ steady_ask` over the category's rules, and `Budget#steady_ask` SURVIVES THE CLAIM MODEL: it
  # is the app's one answer to "what does this rule cost a period", which is what a bar's
  # denominator is, and `ClaimCalculator#rate_per_period` reads the very same method for a rate
  # rule's own share. Nothing about a SCHEDULE is read here — this card prints no due date at all
  # (see the class header) — so the one place the two due-date derivations diverge is a place this
  # file never reaches.
  #
  # ** READ OFF THE CALCULATORS THIS CARD ALREADY HOLDS, NOT OFF A SECOND SET (fix wave 2 — MED-B).
  # ** This was `holding.budgets.sum { |b| b.steady_ask(user, today:) }`, and `#steady_ask`'s one-off
  # branch BUILDS A CALCULATOR — so a category with a one-time bill on it minted a second calculator
  # per rule beside `#claim_calculators`, which is the very defect fix round 1's L5 closed on the
  # edit path. `ClaimCalculator#standing_ask` is the same figure by construction: it IS the one-off
  # arm of `#steady_ask`, and for the other two shapes it delegates straight back to that method.
  # (Under the wave that read `#planned_this_period` those extra calculators also cost two statements
  # each; `#standing_ask` reads no rows, so what is saved now is the object and the second door.)
  #
  # `0.to_d` seeded, because an unseeded `sum` over an empty set returns the Integer literal 0 and
  # #bar_fraction divides by this. It is the same money-type guarantee `Category#claim` keeps one
  # layer up, for the same reason.
  def steady_claim = claim_calculators.sum(0.to_d, &:standing_ask)

  # WHAT THE CATEGORY CLAIMS RIGHT NOW — `Category#claim`'s expression, off the calculators this
  # card has already built (fix round 1 — L5).
  #
  # ** IT WAS `holding.claim(today:)` AND ON THE EDIT PATH THAT BUILT EVERY CALCULATOR TWICE. **
  # `#balance` asks `#own_contribution` FIRST, which reaches `#counted_by_the_claim?` and therefore
  # `#claim_calculators`; wherever one of the three gates then closes, the give-back is zero and
  # `#balance` falls through to this reader — which asked the model for a fresh `ClaimCalculator`
  # per rule and paid for a second spending query and a second adjustment query on each of them.
  # Every re-categorised entry and every back-dated one takes that path. Read ONCE, off the
  # calculators in hand.
  #
  # THE ONE-DOOR RULE IS KEPT BY A PIN RATHER THAN BY A DELEGATION, and the distinction matters:
  # `Budget#claim_calculator` is the same constructor `Category#claim` uses, over the same
  # `#budgets`, summed with the same `0.to_d` seed — this IS that method's expression, not a second
  # opinion about it. `entry_impact_presenter_spec`'s "reads the category's own claim and not a
  # second sum of its rules" asserts the two against each other on a planted literal, so a drift is
  # a failing example rather than two screens printing different money.
  #
  # `.to_d` on the RESULT even though the `sum` is seeded with `0.to_d`: this figure is subtracted,
  # compared and divided by all over this file, and the guarantee costs nothing to restate at the
  # boundary the card actually reads it through.
  def claim = @claim ||= claim_calculators.sum(0.to_d, &:claim).to_d

  # ONE CALCULATOR PER RULE, BUILT ONCE AND SHARED BY EVERY READER BELOW. The NEW-entry card pays
  # for exactly what `Category#claim` used to cost it — one calculator per rule — and the edit card
  # now pays that once instead of twice (see #claim).
  #
  # ASKED FOR THE SHAPE OF THE CLAIM AS WELL AS FOR ITS FIGURE — `#over?`, `#counts_spending_on?`,
  # `#rate?`, `#target`, `#accrued_this_period`, `#standing_ask` (the bar's denominator, fix wave 2 —
  # MED-B) and `#claim` itself. `#countable_span` is NOT among them and must not be: it answers where
  # a typed adjustment may be dated, and this card types none. `Budget#claim_calculator` is the same
  # constructor `Category#claim` uses, so what these objects say about the claim is what that claim
  # is made of.
  def claim_calculators
    @claim_calculators ||= holding.budgets.map { |budget| budget.claim_calculator(today: today) }
  end

  # ** THE SAME SUM `Category#claim` MAKES, READ ONE STEP BEFORE THE CLAMP AT ZERO. ** A rate rule's
  # claim IS `max(0, accrued − spent)` (§3.1), so this drops the `max` and hands #balance a figure
  # the give-back can be added to without the clamp having eaten part of it first. An accruing rule
  # contributes its `built_up`, which is already clamped and whose pre-clamp figure the walk does not
  # keep — gate 3 on #counted_by_the_claim? is what stops that difference from mattering.
  #
  # `max(0, this)` IS `Category#claim` for the ordinary one-rule category, which is why #balance can
  # keep reading the one door on the NEW-entry path and this one only on edit. The two part company
  # on a category mixing an OVERSPENT rate rule with a healthy accruing one, where the sum is taken
  # before the clamp instead of after it and the overspend therefore eats into the sibling's figure.
  # That is the understating direction, and gate 3's note carries the argument for preferring it.
  def pre_clamp_claim
    claim_calculators.sum(0.to_d) do |calculator|
      calculator.rate? ? calculator.raw_rate : calculator.built_up
    end
  end

  # THE MOST THIS CATEGORY COULD POSSIBLY CLAIM — a rate rule's whole accrual for the period (§3.1's
  # `rate + Σ adjustments`, floored at zero because a big enough negative delta would otherwise make
  # the ceiling itself negative), and a CAPPED accruing rule's target (§3.2 caps its built-up there).
  # `#ceiling_for` carries the third arm and why it is what it is.
  #
  # A CATEGORY CARRYING TWO CAPPED ACCRUING RULES COUNTS BOTH CEILINGS, and
  # that is accepted rather than corrected: it makes the ceiling LOOSER, never tighter, so it cannot
  # cut a figure that was true, and the ceiling is the second line of defence behind the three gates
  # on #own_contribution rather than the thing doing the work.
  def most_it_could_claim
    claim_calculators.sum(0.to_d) { |calculator| ceiling_for(calculator) }
  end

  # ** AN UNCAPPED BUILDING RULE HAS NO TARGET TO BE THE CEILING (rules-own-the-budget spec §2.1 row
  # 2; fix round 1 — MED). ** `ClaimCalculator#target` is NIL for a fund that names no figure, and a
  # `BigDecimal + nil` raised on the entry form the moment a category held one.
  #
  # THE CEILING FOR THAT SHAPE IS `built_up + this period's rate`, and the reasoning is the one this
  # method is built on: the ceiling exists to stop a give-back printing money that is provably not
  # there, so it has to be the most the rule COULD hold on the day the card is drawn. An uncapped
  # rule's built-up is whatever the walk has reached; the only thing that can be added to it before
  # the next boundary is this period's own share, and there is no deadline and no cap that could
  # take it higher. It is also the LOOSEST honest bound rather than the tightest, which is the
  # direction this method's own header argues for — the three gates on `#own_contribution` do the
  # work, and the ceiling is the second line of defence behind them.
  def ceiling_for(calculator)
    return [calculator.accrued_this_period, 0.to_d].max if calculator.rate?
    return calculator.target if calculator.capped?

    calculator.built_up + calculator.planned_this_period
  end

  # WHAT THIS ENTRY HAS ALREADY TAKEN OUT OF THE CLAIM, in the claim's own sign. Zero for a new
  # entry, zero for one that drains a category other than the one the card is describing, and zero
  # wherever the claim's arithmetic makes the give-back a guess — see #balance for the three gates
  # and the measurement behind each.
  #
  # NEGATIVE, UNCONDITIONALLY: §3 has one sign for spending on a rule's lane — it subtracts, from a
  # rate rule's period and from an accruing rule's built-up alike. `#render?` keeps income off this
  # path, so there is no second case.
  #
  # THE TEST IS THE LEDGER'S OWN RULE, ASKED TWICE. `ENTRY_CATEGORY_ID` counts an entry against its
  # own category and only from that category's `funded_since` onward, so BOTH halves have to hold:
  # the entry's category must be the one on screen, and its DATE must be one the category counts.
  # A back-dated receipt on a recently funded category moves no claim at all, so giving it back
  # would credit the card with money no rule ever claimed.
  #
  # THE RECORD ON DISK, NOT THE ONE IN THE FORM. Both the date and the amount are facts about what
  # the claim already counted, and the object handed in is not always that: a failed `update`
  # re-renders an `@entry` carrying the REJECTED amount and possibly a different item, so reading
  # `entry.amount` there would remove a figure no claim ever held. `#changed?` is false on every
  # ordinary path (the edit GET, the fragment endpoint), so the reload costs a query only on the
  # one path where the in-memory record is provably not the one on disk.
  def own_contribution
    counted = counted_entry
    return 0.to_d unless counted && counted_by_holding?(counted) && counted_by_the_claim?(counted)

    -counted.amount.to_d
  end

  def counted_by_holding?(counted)
    counted.item.category_id == holding.id && holding.counts_spending_on?(counted.date)
  end

  # ** IS THIS ENTRY IN THE FIGURE AT ALL, AND BY ITS WHOLE AMOUNT? ** #balance's gates 2 and 3,
  # both read off the calculators rather than re-derived here.
  #
  # `#counts_spending_on?` is `ClaimCalculator`'s own answer to which DAYS its walk subtracts
  # spending on — one period for a use-it-or-lose-it rate rule, the whole accrual history for the
  # other two shapes — so an entry from a previous period is simply not in a rate claim and there is
  # nothing of it to give back. `ANY` rule, because the category's claim is a SUM and one rule
  # counting the day is enough for the amount to be inside the figure.
  #
  # ** IT WAS `#countable_span`, AND THAT READER ANSWERS A DIFFERENT QUESTION (fix wave — MED-1). **
  # The span is the days a typed ADJUSTMENT may be dated on and is bounded at `min(today, …)`; the
  # claim's spending predicate has no today bound at all. An entry dated LATER THIS PERIOD is
  # therefore subtracted by the claim and was invisible here, so this method returned false, the
  # give-back was dropped, and the card subtracted the entry a second time — $250 against a truth of
  # $300 on a $300 rate rule with a $50 receipt dated four days out. One predicate, on the class that
  # owns the walk.
  #
  # `#over?` IS ASKED OF THE ACCRUING RULES ONLY, and the exclusion of the rate rules is the whole
  # of gate 3's precision. A rate rule that has been overspent is handled exactly by
  # `#pre_clamp_claim`, which reads the figure before the clamp; an accruing rule's pre-clamp figure
  # is not recoverable (§3.2 clamps inside every period of the walk), so where one of those has gone
  # past what it had the give-back is dropped rather than guessed. See #balance for why the safe
  # direction is to understate.
  #
  # THE DAY IS THE OWNER'S, through `User#local_day`, because the calculator's periods are: a
  # Tokyo user's Sep 1 receipt is stored on Aug 31 in UTC, which on a monthly grid is a different
  # period and therefore a different answer.
  def counted_by_the_claim?(counted)
    day = user.local_day(counted.date)

    claim_calculators.any? { |calculator| calculator.counts_spending_on?(day) } &&
      claim_calculators.none? { |calculator| !calculator.rate? && calculator.over? }
  end

  # The entry AS THE LEDGER HOLDS IT, or nil when the ledger holds none: nothing at all for a new
  # entry, and a reload for the one path where the object handed in is provably not the record on
  # disk. `#changed?` is false on every ordinary path, so the query is not paid for on any of them.
  #
  # SCOPED THROUGH `user.entries`, not `Entry`. The controller already scopes both ids it accepts,
  # so a bare `Entry.find_by` is safe today — and this is the one read on a path that PRINTS A
  # BALANCE, so it should not be safe by argument about a caller. It costs the same query.
  def counted_entry
    return nil unless entry&.persisted?

    entry.changed? ? user.entries.find_by(id: entry.id) : entry
  end
end
