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
# AND IT SPEAKS NO STATUS. `PoolStatus` is the app's most-guarded reader and it is not consulted,
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

  # THE ENVELOPE, DERIVED AND NEVER PICKED (§6): the user chooses a category, the pool follows.
  #
  # `Category#effective_pool` — the model's own reader for "which pool does this category's spending
  # reach", corrected on this branch to agree with `PoolBalanceLedger::ENTRY_POOL_ID`. The ENTRY's
  # own `pool_id` override is not consulted: it has no UI, `EntriesController#entry_params` cannot
  # set it, and the card must describe the pool the chosen CATEGORY reaches or it would answer a
  # question about a different envelope than the one the save will touch.
  def pool = category&.effective_pool

  # THE HONEST CARD (decision 2). Two shapes reach it and both are the same sentence:
  #
  #   * no pool at all — nothing reserves this money, and
  #   * a pool that IS an account — an account is the buffer, so nothing reserves it either.
  #
  # That pair is `Category#buffer_funded?`, the model's own reader and the suggestion engine's
  # population, and its sentence ("currently comes out of your buffer") is the register this card
  # borrows so the two screens say one thing. It is not CALLED here only because it re-asks
  # `expense?`, which `#render?` has already settled: every category that reaches this method is an
  # expense one, so the model's predicate and this pair are the same question with the same answer.
  #
  # THE SECOND ARM IS GONE (plan 3, task 5). `#contribution?` split this card in two — a savings
  # category with nowhere to land got "No goal — this contribution has nowhere to land", pointing
  # at `/pools/new` rather than at the Budget page, because a contribution does not come OUT of the
  # buffer. There is no savings category any more, so there is one honest card and it is the
  # spending one.
  def unbudgeted? = pool.nil? || pool.pool_type_account?

  # A SAVINGS POOL IS A GOAL, so the card takes the goal shape (`$X → $Y of $Z goal`) rather than
  # the envelope's. `target_amount` is the existing goal reader — `PoolCalculator#progress_percentage`
  # and `#remaining_amount` measure against exactly this — and a savings pool with no target set has
  # no goal to show, so it falls back to the envelope shape.
  #
  # KEYED ON THE POOL AND NOT ON THE CATEGORY TYPE, because the two come apart: the demo's Education
  # EXPENSE category points at the Retirement Supplement savings pool, and spending from a goal is
  # still spending against a goal.
  def goal? = pool.present? && pool.pool_type_savings? && pool.target_amount.to_d.positive?

  def goal_target = goal? ? pool.target_amount.to_d : nil

  # "envelope" or "goal" — the noun the header uses, from the pool's own type.
  #
  # `Pool#noun` NOW, AND THIS CARD IS WHERE THAT MAPPING CAME FROM (2d whole-plan review, fix 2).
  # The words are unchanged: this was the one screen already saying "goal" for a savings pool and
  # "buffer" for an account, and the category page's two blocks were moved onto it rather than the
  # other way round. What changes is that the case expression that produced them is no longer a
  # third copy of the classification.
  #
  # THE `nil` ARM STAYS AND CANNOT FIRE FROM THE VIEW. Both call sites sit inside the branch
  # `#figures?` guards, so a card printing this noun has a pool that is neither nil nor an account.
  # The fallback is for the reader that calls it anyway — "envelope" is the right word for spending
  # that reaches no pool, and it is what the honest card's own headline says.
  def noun = pool&.noun || "envelope"

  # WHAT IS IN THE ENVELOPE, AS IF THIS ENTRY WERE BEING DECIDED NOW.
  #
  # `PoolCalculator#balance` and then ONE correction, which is the whole of the edit case: on edit
  # the ledger has ALREADY counted this entry, so a card built straight off the balance would answer
  # "what is left after the spending you already logged" while the user is looking at a form that
  # asks "how much is this". Typing the same figure again would appear to spend it twice. The
  # entry's own contribution is removed so the two figures the card prints are the world without
  # this entry and the world with it — which is the question the screen is asking.
  #
  # Only when the entry actually reaches THIS pool (`Entry#effective_pool`, the same COALESCE the
  # ledger runs on): re-categorising an entry into a different envelope must not credit the new
  # envelope with money it never held.
  def balance = @balance ||= (pool.calculator(today: today).balance - own_contribution).to_d

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
  # no-envelope card has none. Every money reader below is gated on it, because there is no balance
  # to read off a pool that is not there.
  def figures? = render? && !unbudgeted?

  # NEGATIVE IS THE ONLY TEST, and it is a fact about a sign rather than a status. Exactly zero is
  # not overdrawn: spending an envelope to the penny is the tidiest possible outcome and reading it
  # as trouble would be the same lie as `-$0.00`. FALSE with no envelope, and not an error: the
  # submit button asks this on every render of the form, including the ones with no card at all, and
  # spending that nothing reserves cannot overdraw anything.
  def overdrawn? = figures? && balance_after.negative?

  # THE BAR'S DENOMINATOR — what this envelope is FOR, per period.
  #
  # `Σ Budget#steady_ask` over the pool's own rules: steady_ask is the one per-period normaliser on
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

  # `Σ steady_ask` over the pool's rules. `0.to_d` seeded, because an unseeded `sum` over an empty
  # set returns the Integer literal 0 and #bar_fraction divides by this — the money-type guarantee
  # `PoolCalculator` keeps for the same reason, one layer up.
  def steady_claim = pool.budgets.sum(0.to_d) { |budget| budget.steady_ask(user, today: today) }

  # WHAT THE LEDGER ALREADY COUNTS FOR THIS ENTRY, in the ledger's own sign. Zero for a new entry,
  # and zero for one whose money is in a DIFFERENT pool than the card is describing.
  #
  # NEGATIVE, UNCONDITIONALLY (plan 3, task 5). This was `counted.category.savings? ? 1 : -1` — the
  # ledger's own two signs — and the ledger has one sign for entries reaching a pool now: an
  # expense subtracts. `#render?` keeps income off this path, so there is no third case.
  #
  # THE RECORD ON DISK, NOT THE ONE IN THE FORM. Both the sign and the amount are facts about what
  # the ledger already counted, and the object handed in is not always that: a failed `update`
  # re-renders an `@entry` carrying the REJECTED amount and possibly a different item, so reading
  # `entry.amount` there would remove a figure the ledger never held. `#changed?` is false on every
  # ordinary path (the edit GET, the fragment endpoint), so the reload costs a query only on the
  # one path where the in-memory record is provably not the ledger's.
  def own_contribution
    counted = counted_entry
    return 0.to_d unless counted && counted.effective_pool == pool

    -counted.amount.to_d
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
