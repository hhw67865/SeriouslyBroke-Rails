# frozen_string_literal: true

# Computes what a category HOLDS and how that holding is spoken for by its rules.
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2, §3
#
# THE PORT OF `PoolCalculator` (Task 3), and the same class with the noun changed: the money it
# reads is `Allocation`s in and out plus the spending that drains the category (§4's re-anchored
# start-date rule, spelled once in `Entry.draining`), where the envelope read movements and the
# entries that reached its pool. Every decision below — the memos, the money-type guarantee, the
# fill order, the sweep's partiality — was paid for on the pool side and is not re-derived here.
#
# THE LEDGER AS IT STANDS, AND ONLY THAT. The two questions about a ledger nobody has written yet —
# the coming sweep, and the allocations a screen is proposing — live on HoldingProjection, which
# wraps one of these and owns the adjustment arithmetic, the twin it needs and the refusal that
# guards it. What stays here is what this class can answer from rows that exist: `as_of:` (a ledger
# question — which rows had happened by then), `today:` (the clock every calculator shares) and
# `terms:` (the same aggregates, run by somebody else).
class HoldingCalculator
  # THE REFUSAL'S OTHER NAME. The class itself lives on HoldingProjection — the object that raises
  # it — and this is an ALIAS of that one class, not a second error. It exists because the constant
  # is a PUBLIC name: a `rescue HoldingCalculator::NetOfSweepError` written by a caller holding a
  # calculator has to catch the raise, and `raise`/`rescue` compare by object identity, so the two
  # names cannot come to mean different things.
  #
  # IT IS ALSO THE ONE LOAD-TIME REFERENCE BETWEEN THESE TWO CLASSES, and it runs in this direction
  # ONLY. HoldingProjection names HoldingCalculator inside method bodies alone (`.for`, #calculator,
  # #twin, Pending#to_adjustment), so loading this file loads that one and stops. Adding a load-time
  # reference the other way — `adjustment: HoldingCalculator::Adjustment.none` as a default in
  # HoldingProjection's signature is the tempting one — closes the cycle, and it fails in the
  # ugliest available way: this class object exists by then but Adjustment below does not, so it is
  # a NameError on boot rather than a circular-require warning.
  NetOfSweepError = HoldingProjection::NetOfSweepError

  # THE READERS THAT NAME THE SWEEP, in one list because two classes have to agree about them.
  # #sweepable_amount and #period_closed? below answer "what does the next distribution take back",
  # which is the one question a net_of_sweep projection cannot answer — its sweep has already been
  # subtracted, so asking again derives a second, smaller one. HoldingProjection refuses every
  # delegated call whose name is in here (see HoldingProjection#method_missing).
  #
  # A CONSTANT RATHER THAN TWO OVERRIDES THERE, and this is the whole of what it buys: a third
  # reader of the sweep added to this class later is delegated straight past a pair of hand-written
  # overrides and answers with a plausible phantom figure. It cannot walk past a list — but only if
  # whoever writes it knows the list exists, which is why the list is named HERE, beside the readers
  # it is about, and not only in the class that consults it.
  SWEEP_READERS = [:sweepable_amount, :period_closed?].freeze

  # THE PROJECTION SEAM, and the whole of what this class knows about projections: a figure the
  # balance treats as already moved, and the day that money arrived. HoldingProjection computes both
  # and hands them over; see HoldingProjection::Pending, where the reasoning about what they MEAN
  # lives. Nothing here asks what they describe — an adjustment is arithmetic, and this class does
  # not need to know that a screen is proposing anything.
  #
  # TWO MEMBERS RATHER THAN ONE SIGNED NUMBER, and they are read by two different readers for two
  # different reasons: #net is what the BALANCE does, #funded_on is what the CLOCK does (see
  # #last_funded_on). A projection that moved money with no arrival date and a projection that moved
  # none are not the same question, and one number cannot tell them apart.
  #
  # `.none` carries `0.to_d` rather than a bare `0` because #balance sums it with the aggregate
  # terms, and this class's type guarantee is that a money reader never changes shape with how a
  # category is funded — see #balance.
  Adjustment = Data.define(:net, :funded_on) do
    def self.none = new(net: 0.to_d, funded_on: nil)
  end

  attr_reader :category, :today

  # `adjustment:` IS A PROJECTION'S ARITHMETIC, ALREADY DONE — see Adjustment above and
  # HoldingProjection for who computes it. It is applied in exactly two places (#balance and
  # #last_funded_on) and inherited everywhere else, because every other reader here is derived from
  # those: #allocated_balances, #reserve, #free_amount, #sweepable_amount, #required and
  # #period_closed? all read one of them and none of them has to learn about projections.
  #
  # Default `Adjustment.none`, so a calculator built without one is the ledger as it stands and no
  # figure on a screen that asks no projected question can move.
  #
  # `terms:` IS THE SAME AGGREGATES, ALREADY RUN — a `{income:, expense:, movements_in:,
  # movements_out:, last_funded_on:}` hash from `CategoryLedger`, which computes them for a whole
  # SET of categories in one grouped query per term instead of that many per calculator. When it is
  # present the four `*_total` readers and #funded_at return the injected values and NO aggregate
  # runs here; when it is absent this class queries for itself.
  #
  # It is a COST keyword and not a money one, which is the whole of why it is safe: the ledger
  # reproduces each term's scoping line for line — the same `Entry.draining` predicate through
  # `CategoryLedger::ENTRY_CATEGORY_ID`, the same allocation columns, the same `as_of` bound — so an
  # injected calculator and a plain one over the same category are the same numbers.
  #
  # `nil` rather than an empty hash for "not batched": an empty hash is a ledger that answered for a
  # category it does not know, and that must not read as "run your own queries" — it reads as a
  # KeyError instead (see #term).
  #
  # SAME `as_of` OR NOTHING. The ledger bounds its terms by `as_of` itself, so a caller handing
  # terms from one moment to a calculator asking about another gets a balance from neither. One
  # ledger per `as_of`; CategoryLedger carries its own for exactly this reason.
  def initialize(category, as_of: nil, today: category.today, adjustment: Adjustment.none, terms: nil)
    @category = category
    @as_of = as_of
    @today = today
    @adjustment = adjustment
    @terms = terms
  end

  # WHAT THIS CATEGORY HOLDS (§2): what was allocated in, less what was allocated out, less the
  # spending it counts. `CategoryLedger#holding_of` is the same three terms summed for a whole
  # screen, and the two must not be able to disagree — which is why both read the same ledger terms
  # under the same names.
  #
  # THE FOURTH TERM IS INCOME AND IT IS ALWAYS ZERO. It is written down rather than dropped because
  # dropping it would silently break the ledger's contract in the other direction: `CategoryLedger`
  # computes an `:income` key precisely so `#term`'s `fetch`-without-default finds one, and a
  # calculator that never asks would let a ledger stop computing it unnoticed. Income lands in
  # AVAILABLE and never in a category (§2), so the term is a constant rather than a query — see
  # #income_entries_total for the arm that makes it true.
  #
  # `.to_d` on the RESULT. Every `sum(:amount)` term here returns the Integer literal 0 when its set
  # is empty, and a category holding nothing at all — a fresh envelope, the first shape a sweep
  # meets — made them all Integers, so #balance, #reserve, #free_amount and HoldingStatus#balance /
  # #amount all changed TYPE on exactly the categories that are emptiest. Coerced once here so every
  # reader downstream inherits the guarantee, and INSIDE the memo so what is stored is already a
  # BigDecimal. It is belt to `Adjustment`'s braces: the adjustment is a BigDecimal by construction,
  # and the pair is what absorbs a regression in either one alone.
  #
  # Memoised. These are aggregates and almost every other reader in this class starts here —
  # #allocated_balances, #free_amount, #sweepable_amount, #progress_percentage and #remaining_amount
  # all ask — so a single render of a single category would otherwise run them several times over.
  #
  # `||=`, matching #allocated_balances below, and NOT the `defined?` form. That form is reserved in
  # this class for the three readers whose answer is legitimately falsy — #period_closed? (false for
  # most categories), #last_funded_on (nil for a never-funded one) and #fulfilled? (false for every
  # live rule) — where `||=` really would re-run on every hit. This reader cannot return nil or
  # false: `0`, and `BigDecimal("0")` with it, are TRUTHY in Ruby, so `||=` memoises the empty
  # category exactly as well as any other.
  #
  # STALE AFTER A WRITE, deliberately. #allocated_balances, #period_closed?, #last_funded_on,
  # #budgets_by_due_date and #fulfilled? are memoised and every one of them derives from this
  # number, so a calculator held across an allocation or entry write has been answering from a
  # snapshot. The rule callers obey: anything that writes allocations or entries builds fresh
  # calculators afterward.
  def balance
    @balance ||= (income_entries_total + movements_in_total + @adjustment.net -
      movements_out_total - expense_entries_total).to_d
  end

  # Retained for the callers that name a savings figure; identical to #balance.
  alias current_balance balance

  # Earliest due date fills first: the money you need soonest must actually be there.
  #
  # A SETTLED obligation holds nothing, and skips the fill without consuming `remaining` — so the
  # rules behind it in the order receive what it used to hold. Keeping its whole amount forever put
  # two readers of the same category at odds: #free_amount subtracted a paid bill's allocation while
  # #sweepable_amount (which already excludes settled rules) did not, so a screen rendered `$300.00
  # left · last period` on a row the next distribution empties by $900. A screen disagreeing with
  # the action it is offering is the same defect as rendering `$0` for a closed envelope.
  #
  # This cannot move the settled rule's own #required: BudgetCalculator#shortfall returns `0.to_d`
  # for a fulfilled rule BEFORE it looks at `allocated`, so the figure we hand it is already
  # ignored. It does move the category's #required, downward, when a live rule behind it picks up
  # the freed money — that rule is now genuinely funded, and reporting a shortfall against money the
  # category is holding was the same lie one level down.
  #
  # `0.to_d`, not a bare `0`: #reserve sums these values, and the whole class's type guarantee (see
  # #balance) is that a money reader never changes shape with how the category is funded.
  def allocated_balances
    @allocated_balances ||= begin
      remaining = balance
      budgets_by_due_date.index_with do |budget|
        next 0.to_d if fulfilled?(budget)

        # `clamp(0, negative)` raises ArgumentError, which would take down every caller of
        # allocated_balances — reserve, free_amount, required, the whole page. Budget validates the
        # sign, but a validation is an input rule and this is a rendering path: one bad row must not
        # be able to turn a page into a 500.
        taken = remaining.clamp(0, [budget.amount, 0].max)
        remaining -= taken
        taken
      end
    end
  end

  # Seeded, for the category that holds no rules at all: an unseeded `sum` over an empty set returns
  # the Integer literal 0. And `remaining.clamp(0, ...)` hands back the bare `0` low bound whenever
  # the balance is negative, so even a non-empty set can be all Integers.
  def reserve = allocated_balances.values.sum(0.to_d)

  # `.to_d` on the SUBTRACTION, not on the clamp bound. `[x, 0.to_d].max` only coerces when the
  # clamp actually FIRES — `[0, BigDecimal("0")].max` returns the Integer — so seeding the bound
  # alone left every empty category reporting an Integer here, which is the one shape the sweep
  # divides by first. The `max` stays: this must never go below zero.
  def free_amount = [(balance - reserve).to_d, 0.to_d].max

  # A DATELESS GOAL FUNDS AT ITS RATE UNTIL THE CATEGORY REACHES ITS TARGET. A rate rule's usual
  # "satisfied at my own amount" semantics do not apply here: an ordinary rule is satisfied once the
  # envelope holds its amount, which is right for a budget envelope because a budget envelope is
  # swept and topped back up every period. A goal never sweeps, so that same reading would leave a
  # $2,400 goal reporting itself funded forever at $150 — the rule's amount is a contribution RATE,
  # not a per-period ceiling.
  #
  # THE TARGET IS WHAT MAKES IT A GOAL, and that is the one place this port departs from the
  # mechanical rule its brief gave (`pool.pool_type_savings?` → `category.savings?`). The brief
  # predates `Category#savings?`, which is holder + target + NO RULE — the right sentence for the
  # screens that render a goal, and the wrong one to ask HERE, because a goal with no rule has no
  # rate to contribute: asked `savings?`, this branch could only ever fire on a category whose
  # #goal_required is 0, which is what #required already answers without it. The branch would be
  # provably inert and the shapes it protects would fall through to the envelope maths instead.
  #
  # Those shapes are real and the demo builds one: Retirement Supplement is a goal with a $150
  # per-period rule and a $100,000 target, and `savings?` classifies it as an envelope. As an
  # envelope it asks for the rest of ONE period's $150 rather than its rate, and — worse —
  # #period_closed? calls its rate period over and the next distribution sweeps the user's whole
  # retirement balance back to available. Savings accumulate by definition (§7.2 of the envelope
  # spec, unchanged by this model), so they never sweep.
  #
  # TWO DELIBERATELY DIFFERENT CONDITIONS, then, exactly as `PoolStatus#saving?` and
  # `PoolCalculator#dateless_goal?` already were: `Category#savings?` is the display question and
  # this is the funding one. Changing either does not automatically change the other.
  #
  # THE TARGET TEST ITSELF IS #saving_toward_a_target?, spelled once below. What THIS reader adds
  # is the dateless leg, and only for the FUNDING question: a goal that names an anchor_date has a
  # deadline, and the anchored maths already spreads it across the periods remaining, so that path
  # must keep winning. The SWEEP adds no such leg — savings never sweep whatever their rule mix
  # (see #compute_period_closed).
  #
  # ** THE STATUS LEVEL OF TASK 7'S TWO-LEVEL CLASSIFICATION (fix round 1, MED-2). ** The goal
  # question is asked at two levels and they are deliberately different conditions, which is the
  # statement that replaces an earlier "all three screens agree" overclaim:
  #
  #   CHROME — what a card is CALLED and whether it draws a target bar — is #saving_toward_a_target?
  #     everywhere (the impact card's `#goal?`, the holdings card's heading and bar, the categories
  #     index card's bar). A goal is a goal whatever refills it.
  #   STATUS — the row vocabulary's state word — is THIS reader, through `HoldingStatus#saving?`,
  #     and it stays SCHEDULE-AWARE. A dateless goal has no deadline to be measured against, so
  #     `saving` (`$424.00 of $2,400.00`) is the only honest thing to say about it; a goal carrying
  #     an ANCHOR-DATED rule does have one, and the anchored maths already knows whether it will be
  #     met — so it reads `on track`, `behind` or `won't make it`, which is more information rather
  #     than less.
  #
  # `Goal · on track` IS THE PAIRING THAT FALLS OUT OF THAT, and it is a sensible sentence rather
  # than a contradiction: the heading says what the category is, the status says how the schedule is
  # going. The anchored shape is pinned on all three screens (holdings card, impact card, Home row)
  # so neither level can quietly adopt the other's condition.
  def dateless_goal?
    saving_toward_a_target? && rules.none? { |budget| budget.anchor_date.present? }
  end

  # `min(rate, remaining)`: the final contribution is the remainder, not the rate. Asking for $150
  # when $40 would finish the goal overshoots the target the user set.
  #
  # `0.to_d`, not a bare `0`: #required feeds a summing caller, and an Integer leaking out of the
  # reached-goal branch makes the return type depend on how well funded the category is.
  def goal_required
    remaining = category.target_amount.to_d - balance
    return 0.to_d if remaining <= 0

    rate = rules.sum(0.to_d) { |budget| per_period_rate(budget) }
    [rate, remaining].min
  end

  # A rule's amount is per-period or per-month depending on its basis, and Budget blesses both
  # shapes without an anchor. Summing them raw mixes units: a $600-a-month rule would ask $600 every
  # fortnight, more than twice the rate the user set, funding a four-month goal in under two.
  # Normalise to a per-period figure before adding.
  #
  # `Budget#steady_ask`, which is the app's ONE answer to "what does this rule claim from a typical
  # period": $260 a month is $120 a period, always, because 26 periods a year is what biweekly
  # means. A normalisation of this file's own would be a second answer, and the two would drift.
  #
  # Only two shapes reach here: #dateless_goal? requires every rule on the category to be
  # anchorless, and Budget#shape_must_be_valid pins an anchorless rule to per-period or to a 1-month
  # interval. `steady_ask` answers both directly, so this delegates whole rather than branching.
  def per_period_rate(budget) = budget.steady_ask(category.user, today: today)

  # The `sum` seed is the same type guarantee as #goal_required's, for the category that holds no
  # rules at all: an unseeded `sum` over an empty set returns the Integer literal 0.
  def required
    return goal_required if dateless_goal?

    budgets_by_due_date.sum(0.to_d) { |budget| budget.calculator(today: today).required(allocated_balances[budget]) }
  end

  # HOW FULL, AS A WHOLE PERCENT, CLAMPED AT BOTH ENDS.
  #
  # THE FLOOR IS AT THE READER, and it is what keeps every render site from drawing a bar of
  # negative width: an overdrawn category measured against a target answered a NEGATIVE percentage,
  # and "minus thirty percent complete" is not a reading of anything — a bar measures how much of a
  # target is there, and less than none of it is there is still none of it.
  #
  # The type is Integer at both bounds by construction — `.round` on the quotient, and two Integer
  # clamp bounds — so this reader does not carry #balance's money-type guarantee and never did.
  def progress_percentage
    return 0 unless category.target_amount.to_f.positive?

    (balance / category.target_amount * 100).round.clamp(0, 100)
  end

  # `to_d`, not `to_f`: nil-safe in exactly the same way (`nil.to_d` is 0, and an envelope
  # legitimately has no target) without routing a money value through binary floating point. Same
  # `0.to_d` reasoning as #free_amount for the overfunded branch.
  def remaining_amount
    [category.target_amount.to_d - balance, 0.to_d].max
  end

  # A budget envelope whose rate period has ended still holds its leftover — the money is physically
  # there until a distribution moves it. We say so rather than rendering $0, because both partitions
  # of the same total (§2) are the invariant everything rests on.
  #
  # GOALS ARE EXCLUDED BY THEIR TARGET, not by rule shape, and not by SOME rule shapes either — see
  # #compute_period_closed. A dateless goal IS a rate rule on a category, so "has a rate rule whose
  # period ended" would drain every goal the user has, and #free_amount would hand the sweep a
  # plausible figure to take. Savings accumulate by definition, so they never sweep.
  #
  # Measured against the date the money ARRIVED, not against today. BudgetCalculator#period_end
  # answers "when does the period containing `today` end", so `period_end(today) < today` is
  # unreachable by construction. Asking it of the funding date instead is the same sentence about
  # the period that money actually belongs to, and it is the reachable one: $60 allocated on Jul 12
  # sits in a period that ended Jul 23, and today is Aug 20.
  #
  # `all?`, so the LATEST period governs. A category mixing a per-period rule and a monthly one has
  # two different period ends, and until both have rolled some rule still has a live claim on the
  # money. Sweeping at the earlier of the two would take money the monthly rule expects to cover the
  # rest of the month, and #required would then ask for the whole monthly amount again. The
  # conservative direction is the right one for a sweep: money staying put can never break the
  # invariant, and never surprises the user by disappearing.
  #
  # Memoised on `defined?` rather than `||=`, because false is the answer for most categories and
  # `||=` would re-run the whole thing every time it came back.
  #
  # THE REFUSAL THAT GUARDS IT IS HoldingProjection'S, on the object that has a sweep to be wrong
  # about. This calculator answers the question honestly for every caller, because a calculator
  # whose balance has had a sweep taken off it is no longer one of these.
  #
  # THIS AND #sweepable_amount ARE SWEEP_READERS, and a THIRD reader that answers "what would the
  # next distribution take back" belongs in that constant on the day it is written. Delegation
  # projects a new reader automatically; it does not refuse one automatically.
  def period_closed?
    return @period_closed if defined?(@period_closed)

    @period_closed = compute_period_closed
  end

  # What the next distribution would take back. Never more than the balance, and never less than
  # zero: an overspent category has nothing to give, and its deficit is available's problem — a
  # negative sweep would be available paying the envelope on the way out, money moving the wrong way
  # through the ledger.
  #
  # `0.to_d` on the early return, not a bare `0`: that is the branch an empty category takes, and
  # this figure is summed and divided by the distribution.
  #
  # The subtraction is PARTIAL, not all-or-nothing. A category carrying a $500 rent rule and a $100
  # gas rate rule is closed the moment its rate period ends, and it gives back only what the rent is
  # not holding — an all-or-nothing gate on the rent would strand that $100 of genuine leftover in
  # every period, forever, because a recurring rule is never `fulfilled?`.
  def sweepable_amount
    return 0.to_d unless period_closed?

    [(balance - anchored_reserve).to_d, 0.to_d].max.to_d
  end

  # WHAT CAME INTO THIS CATEGORY AND WHAT LEFT IT — the two money-flow figures a category's page
  # names, and the two the purpose ledger is made of.
  #
  # `.to_d` ON THE SUM, and it is the type guarantee holding at the one place `terms:` could
  # otherwise break it. The operands are `0` the Integer on an empty category when this calculator
  # runs its own aggregates, and BigDecimal when a ledger hands them over — so without this, these
  # two readers would change SHAPE with which caller built the calculator, which is exactly what
  # "inert by default" forbids.
  def contributions = movements_in_total.to_d

  def withdrawals = (movements_out_total + expense_entries_total).to_d

  # IS THIS CATEGORY SAVING TOWARD A FIGURE — the goal test, spelled ONCE (fix round 1, LOW-2).
  # Its readers must not be free to drift: #dateless_goal? above (what a goal ASKS for),
  # #compute_period_closed (savings never sweep), `HoldingStatus#saving?` — which reaches it through
  # #dateless_goal? rather than re-deriving a target test of its own — and, since Task 7, every
  # screen that draws a goal as a goal. The readers that add a leg add it in the open, beside the
  # reader that needs it.
  #
  # `holder?` IS PART OF THE TEST AND NOT A GUARD AROUND IT. A category with no `funded_since`
  # holds nothing — its spending drains available (§4) — so a target on it is a goal nothing can
  # progress toward, and it is neither saving nor sweeping. It was the leg the status\'s own copy of
  # this test was missing, which is what made the two copies a divergence rather than a duplication.
  #
  # ** PUBLIC SINCE TASK 7 — THE CHROME LEVEL OF THE TWO-LEVEL CLASSIFICATION (fix round 1,
  # MED-2). ** The entry form's impact card asked `Category#savings?` — holder + target + NO RULE —
  # so the demo's Retirement Supplement (a $100,000 goal carrying a $150 rate rule) drew the
  # ENVELOPE bar there, denominated in Σ steady_ask, an inch under a line reading "of $100,000.00
  # goal". Every RENDERING asks this predicate now: what a category is CALLED (`Goal` / `Envelope`)
  # and whether a target bar is drawn — the impact card, the holdings card and the categories index
  # card.
  #
  # IT DOES NOT FOLLOW THAT ALL THREE SCREENS SAY ONE WORD, and an earlier version of this comment
  # claimed it did. The STATUS level — the row vocabulary's state, on Home, on /budget and on the
  # holdings card's own `Standing` line — stays #dateless_goal?'s, because a goal WITH a deadline
  # has something better to say than `saving`. See that reader's header for the whole argument;
  # what is written here is only which question this one answers.
  #
  # `Category#savings?` survives for the one question it is actually the right sentence for — which
  # categories are the user's savings, on an index that lists them (the dashboard strip).
  def saving_toward_a_target? = category.holder? && category.target_amount.to_d.positive?

  private

  # The body of #period_closed?, split out only so the memo above it stays one line of bookkeeping
  # rather than wrapping four guards.
  #
  # The marker means exactly what it says — this category's RATE period has ended. It carries no
  # opinion about its dated bills; #sweepable_amount subtracts what those hold.
  #
  # SAVINGS NEVER SWEEP, FULL STOP, AND THE GUARD IS #saving_toward_a_target? RATHER THAN
  # #dateless_goal? (fix round 1, MED-1). Those two differ on exactly one shape and it is a shape
  # the app can hold: a goal carrying a rate rule AND a dated one. #dateless_goal? is false for it —
  # correctly, because the anchored maths owns its FUNDING — and gating the sweep on that same
  # predicate let it fall straight through to the envelope path. Measured on Vacation (target
  # $2,400, a $150 per-period rule beside a $300 dated one, $600 allocated last period):
  # `period_closed?` true and `sweepable_amount` $300, which is the user's savings going back to
  # available on the next distribution.
  #
  # The pool era could not reach that shape because `pool_type_savings?` refused EVERY savings sweep
  # by TYPE, and no rule mix could argue with a type. The type is gone and the target replaces it,
  # so the refusal has to be restated at the same width: what is being saved toward a figure is not
  # spare money at the end of a period, however many rules the user has hung on it. Task 1's fold
  # re-parents a savings pool's rules onto the minted category, so the mix is live on real data.
  #
  # FUNDING AND SWEEPING ARE THEREFORE ASKED TWO DIFFERENT QUESTIONS OF ONE PREDICATE: #dateless_goal?
  # adds the dateless leg because a rate is only the right ask where no deadline is spreading the
  # goal already; this guard adds nothing, because there is no rule mix that makes savings sweepable.
  def compute_period_closed
    return false unless category.holder?
    return false if saving_toward_a_target?

    rate_budgets = rules.reject { |budget| budget.anchor_date.present? }
    return false if rate_budgets.empty?
    return false if last_funded_on.nil?

    rate_budgets.all? { |budget| budget.calculator(today: last_funded_on).period_end < today }
  end

  # What an unpaid dated bill is already holding. #sweepable_amount is otherwise the whole category,
  # so a mixed one would sweep the rent to top up available on the strength of its gas rule alone.
  #
  # Reserved by ALLOCATION, not by the rule's amount: #allocated_balances is already this class's
  # single answer to which rules the money is covering, and it fills earliest-due first, so an
  # under-funded category reserves what the bill actually has rather than what it wants. A second
  # notion of reserve here would be a second answer to the same question, free to disagree with
  # #reserve and #free_amount.
  def anchored_reserve
    allocated_balances.sum(0.to_d) { |budget, allocated| live_anchored?(budget) ? allocated : 0.to_d }
  end

  # `fulfilled?` is BudgetCalculator's only "no longer live" signal and it is deliberately narrow —
  # only a one-time rule can ever be settled, because a recurring rule always has a next occurrence
  # to fund. A recurring dated bill therefore reserves in every period, which is correct: the money
  # is genuinely spoken for. What is not correct is letting that stop the rest of the category from
  # sweeping.
  def live_anchored?(budget) = budget.anchor_date.present? && !fulfilled?(budget)

  # One spelling of "settled", for the two readers that ask. #allocated_balances asks it to decide
  # whether the rule holds any of the balance; #live_anchored? asks it to decide whether the rule's
  # holding survives a sweep. A second spelling would let those two answers drift.
  #
  # Memoised because those two readers ask about the same rule on the same render, and
  # BudgetCalculator#fulfilled? does not memo its own #paid_since_anchor: each call is a fresh
  # calculator running a fresh SUM over the item's entries.
  #
  # `fetch` with a block, not `||=`. FALSE is the answer for every live rule — the common case by
  # far, and the one the memo most needs to hold — and `||=` re-runs on a false hit, which is the
  # same trap #period_closed? and #last_funded_on dodge with `defined?`.
  def fulfilled?(budget)
    @fulfilled ||= {}
    @fulfilled.fetch(budget) { @fulfilled[budget] = budget.calculator(today: today).fulfilled? }
  end

  # The last day money entered this category — the period #period_closed? is actually asking about.
  #
  # The money-IN term of #balance, and only that: what was spent out of the category says nothing
  # about which period funded it. LAST rather than first, because the money sitting here now belongs
  # to the most recent funding — a stray $5 arriving today makes the category current, which errs
  # toward leaving money alone.
  #
  # `defined?` rather than `||=`: nil is the answer for a never-funded category and the common one
  # (a fresh envelope is exactly the shape a sweep meets first), and `||=` would re-run the
  # aggregate every time it came back.
  #
  # `.to_date` because `allocations.date` is a datetime while every calculator here works in whole
  # days; TimeWithZone#to_date resolves in the request's zone, as DateContext expects. It stays HERE
  # rather than moving into the ledger with the query: the ledger is built once per screen while the
  # zone that matters is the request's.
  #
  # The ADJUSTMENT'S date is added AFTER the batched value and never travels through the ledger. It
  # is a property of what THIS calculator is projecting — one screen's unwritten distribution —
  # while the ledger describes rows that exist; folding it in would make one shared ledger answer
  # differently for two calculators over the same category.
  #
  # `.compact.max` and not `@adjustment.funded_on || funded_at`: a projection dated today over a
  # category funded yesterday and one over a category funded next month are different worlds, and
  # LAST is the rule (see above). Both are nil on a never-funded category with nothing projected
  # into it, and that nil is the answer the `defined?` memo exists to hold.
  def last_funded_on
    return @last_funded_on if defined?(@last_funded_on)

    @last_funded_on = [funded_at, @adjustment.funded_on].compact.max&.to_date
  end

  # THE MAX(date), BEHIND THE SAME GATE AS THE SUMS. Injected when a ledger ran it for the whole
  # category set, and run here when it did not, over exactly the money-IN scope of #balance.
  #
  # THERE IS ONE WHERE THE POOL HAD TWO, and the missing one is income: income never lands in a
  # category, so there is no income date to be the latest funding (see #income_entries_total).
  #
  # The pre-`to_date` maximum rather than the finished answer, because that is what the ledger can
  # honestly compute: a TimeWithZone or nil, the same shape `maximum(:date)` returns below. Nil
  # travels through `term` untouched — `@terms.fetch` finds the key and returns its nil value rather
  # than yielding — which is what keeps #last_funded_on's `defined?` memo from re-running an
  # aggregate on the never-funded category this whole reader exists to answer nil for.
  def funded_at
    term(CategoryLedger::FUNDED_ON) { scoped(category.allocations_in).maximum(:date) }
  end

  # The sort key is a triple, not a bare due date, and it is BudgetCalculator#due_order's — the one
  # place that rule lives, shared with HoldingStatus#anchored_budgets and the presenters that name a
  # rule. `sort_by` is not stable and `category.budgets` carries no ORDER BY, so two rules sharing a
  # due date could otherwise swap fill order between calls: the same category reporting different
  # #required figures on consecutive loads with no data change.
  def budgets_by_due_date
    @budgets_by_due_date ||= rules.sort_by { |budget| budget.calculator(today: today).due_order }
  end

  # THE CATEGORY'S RULES, READ OFF THE ASSOCIATION — the same `category.budgets` #dateless_goal?,
  # #goal_required and #compute_period_closed enumerate, and that consistency is the point rather
  # than a side effect. A relation with `includes` on it would be a NEW relation and therefore a
  # fresh SELECT whatever the caller had already preloaded, and it would leave this class
  # disagreeing with itself about which rules the category has.
  #
  # THE PRELOADER RATHER THAN `includes`, and it is what keeps the N+1 away without re-querying:
  # given records whose associations are already loaded it runs NOTHING, and given records without
  # them, one query for the whole set.
  #
  # `[:item, :category]` AND NOT `PoolCalculator`'s `[:item, :pool]` — the ruling carried out of
  # Task 2's review, which measured that reader N+1ing through the category arm of `Budget#user`
  # that the migration had just populated. Both legs are on the #required path:
  # `BudgetCalculator#fulfilled?` and `#overdue?` read `budget.item` for every dated rule, and
  # `#periods_until_due` reads `budget.user`, which a category-owned rule answers through
  # `category.user`.
  #
  # `:item` IS WHAT IT BUYS AND `:category` IS BELT TO THE ASSOCIATION'S BRACES, measured on six
  # item-bearing dated rules over a freshly loaded category and pinned in holding_calculator_spec:
  # 1 items load with this line and 6 without it; the users load is 1 either way, because reading
  # the rules off `category.budgets` means `has_many :budgets`' automatic `inverse_of` has already
  # handed each rule back the very category it came from. `:category` stays for the reason
  # PoolCalculator gave for keeping `:pool` at the same measured zero: it costs nothing, and it is
  # the one thing standing between `Budget#user`'s category arm and a lookup per rule if that
  # inverse is ever lost.
  #
  # MEMOISED, unlike its pool-side ancestor, because this one has four callers rather than one:
  # #dateless_goal?, #goal_required and #compute_period_closed all enumerate the rules and
  # #budgets_by_due_date sorts them. Re-running the Preloader is a no-op, but the `to_a` dup is per
  # call, and #dateless_goal? is asked on the #required path of every category on a screen.
  def rules
    @rules ||= category.budgets.to_a.tap do |budgets|
      ActiveRecord::Associations::Preloader.new(records: budgets, associations: [:item, :category]).call
    end
  end

  # EVERY AGGREGATE, EACH BEHIND THE SAME GATE. `term` returns the injected value when this
  # calculator was handed a ledger's terms and otherwise runs the block, so the query and the
  # batched answer sit in one place per term and cannot describe different scopes.
  #
  # `fetch` without a default, deliberately: a terms hash missing a key is a ledger that does not
  # compute what this class needs, and the loud KeyError is the only honest answer. A `0.to_d`
  # default here would report a category holding nothing — a wrong number, silently, on the one path
  # this whole keyword exists to make cheaper.
  #
  # `fetch` IS ALSO WHAT MAKES THE DATE TERM'S NIL SAFE, and it is key-aware rather than
  # truthiness-aware — which is the whole distinction. `last_funded_on` is legitimately nil for a
  # never-funded category, so the tempting `@terms[name] || yield` would read that real answer as a
  # miss and run the aggregate anyway, on exactly the emptiest categories this term exists to answer
  # cheaply.
  def term(name)
    return @terms.fetch(name) if @terms

    yield
  end

  # INCOME NEVER LANDS IN A CATEGORY (§2), so this is a constant rather than a query — the same
  # answer `CategoryLedger` reaches by computing an empty hash for the term, and reached the same
  # way: `CategoryLedger::ENTRY_CATEGORY_ID` resolves an income category's entries to NULL, so a
  # query here could only ever sum an empty set. It goes through `term` anyway, because the KEY is
  # the ledger's contract and a calculator that stopped asking would let the ledger stop answering.
  def income_entries_total = term(:income) { 0.to_d }

  # WHAT THIS CATEGORY'S SPENDING DRAINS, asked with the ledger's own rule. `Entry.draining` is
  # `CategoryLedger::ENTRY_CATEGORY_ID` narrowed to one id — the funded-since gate and the owner's
  # calendar day included — so the balance and the batched figure cannot describe different rows.
  def expense_entries_total
    term(:expense) { scoped(Entry.expenses.merge(Entry.draining(category))).sum(:amount) }
  end

  def movements_in_total = term(:movements_in) { scoped(category.allocations_in).sum(:amount) }

  def movements_out_total = term(:movements_out) { scoped(category.allocations_out).sum(:amount) }

  # `CategoryLedger#scoped`, and deliberately the same expression: `date` is a datetime column on
  # both tables here too, and the bound is inclusive.
  def scoped(relation)
    @as_of ? relation.where(date: ..@as_of) : relation
  end
end
