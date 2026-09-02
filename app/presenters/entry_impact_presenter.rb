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
# PLAN DECISION 1 — THIS CLASS COMPUTES NO NEW FIGURE. Every number below is an existing reader:
#
#   * the balance is `PoolCalculator#balance` (ledger-backed, the one answer to "what is in this
#     envelope"),
#   * the bar's denominator is `Σ Budget#steady_ask` over the envelope's own rules — steady_ask is
#     THE per-period normaliser on this branch and a local division would be a second one, which
#     is the mixed-unit trap that has struck five times here,
#   * the date is the edge `User#period_boundaries` puts after today, taken through
#     `User#period_containing` so the window arithmetic is not spelled twice.
#
# AND IT SPEAKS NO STATUS. `HoldingStatus` is the app's most-guarded reader and it is not consulted,
# not here and not in the browser: the card renders figures, a bar and a date. There is no "behind",
# no "on track", no colour band standing in for one. The one colour it does use is the ordinary
# negative-money red the account header already uses for a negative buffer — a fact about a sign,
# not a verdict about an envelope.
#
# PLAN DECISION 2 — OVERDRAWING WARNS AND NEVER BLOCKS, and a category with no envelope is told the
# truth rather than shown an envelope that does not exist. See #unbudgeted? and #overdrawn?.
#
# THE INVARIANT IS UNTOUCHED BY CONSTRUCTION: `Σ pools == your bank balance` can only be moved by a
# write, and this class has none. Every figure it prints is read.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §6
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

  def initialize(user:, category:, amount: nil, entry: nil, today: Date.current)
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
  # asked about a day before it started holding, both answer nil here: their spending drains
  # AVAILABLE, not the category, and the honest card below says so.
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

  # THE HONEST CARD (decision 2). ONE shape reaches it now: a category that is not holding money on
  # this day, so the spending drains AVAILABLE — money with no job yet (§2).
  #
  # THE TWO SHAPES IT USED TO BE were "no pool at all" and "a pool that IS an account", and they
  # were one sentence because an account is the buffer and nothing reserved money sitting in one.
  # That pair was `Category#buffer_funded?`; its successor is `Category#holder?`, asked with a date
  # because a holder still drains available for spending that predates its funding.
  #
  # The register is the Budget page's own — its rate suggestion says a category's spending
  # "currently comes out of what's available" of exactly this population — so a user who meets the
  # sentence here and the offer there is reading one app.
  def unbudgeted? = holding.nil?

  # A SAVINGS CATEGORY IS A GOAL, so the card takes the goal shape (`$X → $Y of $Z goal`) rather
  # than the envelope's. `Category#savings?` is the app's DISPLAY question — holder, with a target,
  # carrying no refill rule (§3: "a savings category is just a category with a target and typically
  # no refill rule") — and it is deliberately NOT `HoldingCalculator#dateless_goal?`, which is the
  # FUNDING question and answers true for a goal that also carries a rate rule. The card is a
  # rendering, so it asks the rendering question.
  #
  # Spending from a goal is still spending against a goal, which is why this arm exists at all: the
  # figures are the same two figures, and only the trailing phrase differs.
  def goal? = category.present? && category.savings?

  def goal_target = goal? ? category.target_amount.to_d : nil

  # "envelope" or "goal" — the noun the header uses.
  #
  # `Pool#noun` IS GONE with the type it read: a pool had three types and a word for each, and a
  # category has one type and a question. "envelope" is the right word for a category that holds its
  # own spending money, and it is also the fallback the honest card's own headline is written in.
  def noun = goal? ? "goal" : "envelope"

  # WHAT THE CATEGORY HOLDS, AS IF THIS ENTRY WERE BEING DECIDED NOW.
  #
  # `HoldingCalculator#balance` and then ONE correction, which is the whole of the edit case: on edit
  # the ledger has ALREADY counted this entry, so a card built straight off the holding would answer
  # "what is left after the spending you already logged" while the user is looking at a form that
  # asks "how much is this". Typing the same figure again would appear to spend it twice. The
  # entry's own contribution is removed so the two figures the card prints are the world without
  # this entry and the world with it — which is the question the screen is asking.
  #
  # Only when the entry actually drains THIS category (see #own_contribution): re-categorising an
  # entry must not credit its new category with money it never held.
  #
  # `Category#holding_calculator`, the ONE door onto what a category holds — never
  # `HoldingCalculator.new`, and never `Category#calculator`, which is the unrelated per-period
  # spending reader the categories and dashboard screens ask.
  def balance = @balance ||= (holding.holding_calculator(today: today).balance - own_contribution).to_d

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
  # `#direction` was `+1` for a savings category and `-1` otherwise, because `PoolCalculator#balance`
  # used to ADD savings entries. It no longer does, and there is no savings category to sign: every
  # card this class renders describes an expense (income is silent — see `#render?`), and an expense
  # takes money out of whatever pool it reaches. The GOAL arm is unaffected and still renders —
  # spending from a goal is spending against a goal, which is `#goal?`'s own note.
  def balance_after = @balance_after ||= (balance - amount).to_d

  # WHETHER THERE ARE FIGURES TO PRINT AT ALL — the envelope and goal cards have them, the honest
  # not-holding card has none. Every money reader below is gated on it, because there is no holding
  # to read off a category that is not holding anything.
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
  # A GOAL MEASURES AGAINST ITS TARGET INSTEAD, and this is a CORRECTION to the plan's wording
  # ("the bar's denominator is Σ steady_ask") rather than an exception to its ruling — the ruling is
  # that the card invents no normaliser, and `target_amount` is the existing goal reader that
  # `PoolCalculator#progress_percentage` and `#remaining_amount` already measure against. Measured
  # on the demo seeds, both halves:
  #
  #   * Retirement Supplement holds $545 against a $100,000 goal and $150 a period of rules. Under
  #     the steady_ask denominator its bar is drawn FULL while the line directly above it reads
  #     "of $100,000.00 goal" — two answers to one question, an inch apart, on the same card.
  #   * The other four savings pools (Emergency Fund, House Down Payment, New Car, Vacation to
  #     Europe) carry NO rules at all, so Σ steady_ask is zero and their bars could never move —
  #     empty on a goal the user is watching fill.
  #
  # The envelope case is untouched: a budget pool's bar is Σ steady_ask, exactly as ruled.
  def denominator = @denominator ||= goal_target || steady_claim

  # WHETHER THERE IS A BAR AT ALL. An envelope with no rules on it has no per-period claim, so
  # there is nothing for a bar to be a fraction OF — and an empty track drawn beside real figures
  # says "nothing left" an inch under a line saying $240.00, which is the same two-answers-on-one-
  # card defect that moved the goal's denominator. No denominator, no bar.
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

  # `Σ steady_ask` over the category's rules. `0.to_d` seeded, because an unseeded `sum` over an
  # empty set returns the Integer literal 0 and #bar_fraction divides by this — the money-type
  # guarantee `HoldingCalculator` keeps for the same reason, one layer up.
  def steady_claim = holding.budgets.sum(0.to_d) { |budget| budget.steady_ask(user, today: today) }

  # WHAT THE LEDGER ALREADY COUNTS FOR THIS ENTRY, in the ledger's own sign. Zero for a new entry,
  # and zero for one that drains something other than the category the card is describing.
  #
  # NEGATIVE, UNCONDITIONALLY: the purpose ledger has one sign for an entry that reaches a category
  # — an expense subtracts (`CategoryLedger#holding_of`). `#render?` keeps income off this path, so
  # there is no second case.
  #
  # THE TEST IS THE LEDGER'S OWN RULE, ASKED TWICE. `ENTRY_CATEGORY_ID` counts an entry against its
  # own category and only from that category's `funded_since` onward, so BOTH halves have to hold:
  # the entry's category must be the one on screen, and its DATE must be one the category counts.
  # A back-dated receipt on a recently funded category drains available in the ledger, so removing
  # it here would credit the card with money the category never held.
  #
  # THE RECORD ON DISK, NOT THE ONE IN THE FORM. Both the date and the amount are facts about what
  # the ledger already counted, and the object handed in is not always that: a failed `update`
  # re-renders an `@entry` carrying the REJECTED amount and possibly a different item, so reading
  # `entry.amount` there would remove a figure the ledger never held. `#changed?` is false on every
  # ordinary path (the edit GET, the fragment endpoint), so the reload costs a query only on the
  # one path where the in-memory record is provably not the ledger's.
  def own_contribution
    counted = counted_entry
    return 0.to_d unless counted && counted_by_holding?(counted)

    -counted.amount.to_d
  end

  def counted_by_holding?(counted)
    counted.item.category_id == holding.id && holding.counts_spending_on?(counted.date)
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
