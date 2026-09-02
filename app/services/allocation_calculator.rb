# frozen_string_literal: true

# What the next distribution would do to the PURPOSE LEDGER, and nothing else: this class WRITES
# NOTHING. It sweeps what belongs to a closed period, adds it to the money that has no job yet, asks
# every holder category what it needs, and fills them top-down by priority until the money runs out.
# AllocationCommitter turns the answer into Allocation rows.
#
# ONE WATERFALL OVER ONE ROOT (two-ledger spec §2). The pool era ran one of these PER ACCOUNT,
# because each account had a buffer of its own to hand out. The purpose ledger has a single root —
# AVAILABLE, money with no job yet — so there is one distribution per period per user, and neither
# an account nor a pool is read anywhere below. That is not a simplification of the old shape, it is
# the model: allocating money is an act of intention rather than of location, which is why "any
# account's money can back any category" is automatic here rather than a feature.
#
# COST, for whoever renders this. `sweepable_amount` is computed TWICE for every category: once by
# #sweeps, and once more inside the plain twin that #ask_calculator_for's `net_of_sweep` calculator
# builds for itself. The two agree because nothing writes between them, not because they share an
# object — and that independence is deliberate, since a proposal whose ask and whose sweep could
# disagree is worse than a slow one. The lever, if a screen turns out slow, is to thread the
# already-computed `sweeps[category]` figure into the calculator instead of letting it re-derive its
# own — one reader, passed rather than repeated. Do not reach for it before the screen is measurably
# slow.
#
# STALE AFTER A WRITE, by construction and on purpose. Every figure here is memoised, and the
# HoldingCalculators underneath memoise their balances — so a proposal held across an allocation
# write keeps answering from the snapshot it was built on. That is right for a proposal, whose whole
# job is to describe one moment before anything moves, and it is the reason the committer must build
# FRESH calculators after it writes rather than reusing these. Do not hand a proposal's calculators
# to anything that writes.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2 and
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §5, §7.2
class AllocationCalculator
  # `short` rather than a stored field: it is `needed - funded` by definition, and a fourth member
  # would be a second place for the same number to be wrong.
  Row = Struct.new(:category, :needed, :funded, keyword_init: true) do
    def short = needed - funded
  end

  # `user` IS THE WHOLE CONTEXT NOW, where it used to be the ownership half beside an `account`
  # whose arithmetic this was. There is one root per user and it is the user's, so the question
  # "whose distribution is this" and the question "what is being distributed" have one answer.
  attr_reader :user, :today, :overrides

  # `overrides` is `{category_id => amount}` exactly as a form submits it, and it belongs HERE
  # rather than on AllocationCommitter, where it used to be applied by substituting figures onto an
  # already-finished fill.
  #
  # THAT WAS TWO READERS OF ONE DECISION and it had a visible cost: by the time the committer
  # substituted, the waterfall was over, so money freed by cutting a high row could not reach the
  # category below it. The screen then said "$488.43 of what your categories asked for isn't there"
  # while holding $35 that could have funded some of it — a screen contradicting itself, and the
  # opposite of what someone lowering one category so another survives is asking for. Applied inside
  # #fill, an override simply replaces that row's ask and `remaining` carries on down by the
  # mechanism that was always there. Nothing new decides anything.
  #
  # BLANK MEANS "NO OVERRIDE", NOT ZERO, and this inverted when the form did: every box used to be
  # pre-filled with the proposal's own figure, so a cleared box meant "give it nothing". Boxes now
  # render EMPTY with the proposal as their placeholder, so a blank is a row the user did not touch
  # — and it must fall through to the rule's ask, or a submitted form would pin every untouched row
  # at its old figure and no money could ever cascade. "Give it nothing" is typed as `0`.
  #
  # Coerced once, here, so nothing downstream has to wonder whether it is holding a String.
  #
  # THERE IS NO `ledger:` KEYWORD HERE, DELIBERATELY, AND THAT IS THE POINT OF #share_ledger. A
  # shared ledger is safe under one condition and one only — the sharer was CONSTRUCTED after the
  # last write, so its snapshot cannot pre-date it — and the only object that can honestly promise
  # that about another is another instance of this class, built for the same user on the same day. A
  # constructor keyword would have offered the same thing to every caller in the app on the strength
  # of a comment; #share_ledger is `protected`, so the offer is unreachable from outside instead of
  # merely discouraged.
  def initialize(user:, today: Date.current, overrides: {})
    @user = user
    @today = today
    @overrides = overrides.transform_keys(&:to_s)
      .compact_blank
      .transform_values(&:to_d)
  end

  # THE SAME DISTRIBUTION WITH A DIFFERENT SET OF OVERRIDES, over THIS proposal's ledger.
  #
  # The distribution screen runs the waterfall more than once for one render: the live fill, the
  # baseline fill it compares against ("what would have happened had nothing been edited"), and one
  # fill per edited row with that edit undone. Four fills with two edits, and each used to build a
  # ledger of its own over the same categories at the same moment — several grouped queries apiece
  # for figures that are identical by construction.
  #
  # `user` and `today` are read off THIS object rather than passed in again, which is the other half
  # of what this method is for: the two of them plus the ledger have to describe one moment, and
  # three keywords at a call site are three chances for one of them not to.
  #
  # WHEN SHARING IS SAFE, precisely, because this is the class AllocationCommitter writes from:
  #
  #   A ledger is a snapshot. CategoryLedger memoises each grouped query at its FIRST READ, so two
  #   fills sharing one are answering about the same instant — which is exactly right for two fills
  #   of one render that describe the same instant, and exactly wrong across a write.
  #
  #   THE COMMITTER'S DELETE BOUNDARY IS NOT CROSSED BY THIS METHOD and cannot be.
  #   AllocationCommitter#replace_previous_distribution destroys this period's rows and then builds
  #   #live_proposal with a bare `AllocationCalculator.new` — no ledger — so the re-derivation still
  #   runs its own aggregates over the post-deletion world, which is the property its re-run examples
  #   guard. Only the fills the SCREEN builds off that already-fresh proposal share it, and nothing
  #   writes between them.
  #
  # THE STRONGEST FORM OF THAT GUARANTEE IS ABOUT CONSTRUCTION, NOT ABOUT MATERIALISATION, and it is
  # worth stating because it is what makes the lazy `@ledger ||=` below harmless: the twin is built
  # HERE, from an object that already exists, so its ledger cannot pre-date that object no matter
  # when its grouped queries actually run.
  #
  # `.tap` WITH A PROTECTED WRITER RATHER THAN A CONSTRUCTOR KEYWORD: see #initialize. The object is
  # complete before it is returned, so nothing outside ever sees a half-built one; what is bought is
  # that no caller anywhere else can supply a ledger at all.
  def with_overrides(overrides)
    self.class.new(user: user, today: today, overrides: overrides)
      .tap { |twin| twin.share_ledger(ledger) }
  end

  # Whether the USER typed a figure into this row, as opposed to this row's figure having moved
  # because an override above it freed money. The screen needs the difference: a consequence line
  # belongs to the row that was edited, and a category that was simply reached by the waterfall was
  # not edited.
  def overridden?(category) = overrides.key?(category.id.to_s)

  # What the next distribution takes back, keyed by the category it comes from.
  #
  # There is NO `period_closed?` filter here, deliberately. #sweepable_amount already returns
  # `0.to_d` unless the period is closed, so a second gate would be a second answer to the same
  # question, free to disagree with the amount actually being taken. `positive?` alone keeps the
  # zero rows out — including the closed-but-empty category and the overdrawn one, neither of which
  # has anything to give.
  #
  # SAVINGS ARE ABSENT BECAUSE THE CALCULATOR REFUSES THEM, not because this method knows about
  # them. `HoldingCalculator#compute_period_closed` answers false for any target-bearing category
  # whatever its rule mix (Task 3, fix round 1), so a goal's `sweepable_amount` is zero at the
  # source. Nothing here re-states that rule; there is one place it lives, and the pool era's
  # equivalent gate was by pool TYPE, which no longer exists.
  def sweeps
    @sweeps ||= categories.each_with_object({}) do |category, swept|
      amount = calculator_for(category).sweepable_amount
      swept[category] = amount if amount.positive?
    end
  end

  def total_swept = sweeps.values.sum(0.to_d)

  # MONEY WITH NO JOB YET, PLUS THE SWEEPS, and the addition is not double-counting. Swept money is
  # inside the user's total but not inside available: it is sitting in a category, and the sweep is
  # what moves it back to the root. `CategoryLedger#available` already excludes it, because funding
  # the category was an allocation out.
  #
  # Not clamped at zero. A root that has been allocated past what came in genuinely has less than
  # nothing to hand out, and #fill's per-row clamp already refuses to fund from a negative pot — so
  # the overdraft survives into #leftover, where it is a fact the screen must state, rather than
  # being quietly rounded up to "nothing left".
  #
  # The trailing `.to_d` FIRES NO MUTATION today and is kept anyway, for the reason
  # HoldingCalculator#free_amount keeps its own: both operands are already coerced at their own
  # source, and this is the figure every row's clamp is measured against — the one place the type
  # guarantee should hold locally rather than by inheriting one a later edit could quietly withdraw.
  def available
    @available ||= (ledger.available + total_swept).to_d
  end

  # One row per category that asks for something, in the order the money reaches them.
  def rows
    @rows ||= fill
  end

  # MONEY THAT WILL ACTUALLY LEAVE AVAILABLE, which is not quite `Σ funded`: a negative row — only
  # reachable from a negative override, which #row_for deliberately carries through so it fails
  # Allocation's validation loudly — is money that never moves, because the allocation is refused and
  # the whole commit rolls back.
  #
  # Summed raw it made #leftover LARGER than the root holds: a -$50 row rendered available $50 high,
  # and that line is the one figure on this screen that must never overstate. It is not an
  # over-allocation and the commit still fails, but a user reading money that is not there is the
  # failure mode §7.3 exists to prevent, stated in the other direction.
  def total_allocated = rows.sum(0.to_d) { |row| [row.funded, 0.to_d].max }

  # What stays unallocated. Derived from #available rather than recomputed, so the proposal cannot
  # hand out more than it said it had.
  def leftover = available - total_allocated

  # Answers the question the distribution SCREEN branches on: does any category end this distribution
  # with less than it asked for? Read off the rows, never off `total_allocated < Σ needed` — those
  # disagree the moment a zero-need category or a rejected row enters the picture, and only the rows
  # can say WHICH category is starved.
  def short? = rows.any? { |row| row.short.positive? }

  protected

  # ONE INSTANCE HANDING ANOTHER ITS OWN SNAPSHOT, and `protected` is the whole mechanism: in Ruby it
  # means the RECEIVER has to be an AllocationCalculator too, which is exactly the condition under
  # which the promise in #with_overrides holds — only another fill of the same user on the same day
  # can honestly claim to have been constructed at the same moment.
  #
  # It sits between the public readers and #ledger's memo on purpose: this is the one writer of
  # `@ledger` that is not that memo, and a reader looking for how a ledger gets in here should find
  # both without going hunting.
  #
  # SAME `as_of` OR NOTHING, raised rather than trusted — CategoryLedger owns the rule and the
  # message (see #for_as_of!). `nil` is what this class's own ledgers carry, because #ledger builds
  # one with no bound; a bounded ledger arriving here describes a different world and there is no
  # figure it could produce that would be right.
  def share_ledger(other)
    @ledger = other.for_as_of!(nil)
  end

  private

  # ONE READ, ONE ORDER, shared by the sweep and the fill so the two can never disagree about which
  # categories are in this distribution. `Category.in_fill_order` is holders — expense categories
  # that have started holding money — ordered `[priority, name]`; priority alone is not a total order,
  # and a tie falling through to database order means random UUID bytes deciding which category gets
  # funded.
  def categories
    @categories ||= user.categories.in_fill_order.to_a
  end

  # Spends `remaining` down as it goes, so each category is funded out of what the ones above it left
  # behind — that IS the waterfall, and it is also the only thing an override has to touch: replace
  # one row's ask and every row below it re-fills by itself.
  #
  # ZERO-ASK ROWS ARE REJECTED BEFORE THE FILL RATHER THAN AFTER IT, and the order became
  # load-bearing the moment overrides arrived. Before, rejecting first "could not change the
  # arithmetic" because a zero-ask row funds zero and consumes nothing — that is no longer true: an
  # override naming a category the proposal has no row for would consume `remaining` on its way to
  # being thrown away, funding a category the user cannot even see and starving the ones below it.
  # The rule that survives unchanged is the one that matters: the reject is measured against the
  # CATEGORY'S OWN ASK, never against the overridden figure, so an override on a rowless category is
  # still ignored while a row the user typed a zero into keeps its row and its box — there has to be
  # somewhere to type the money back in. A "$0.00 of $0.00" line below the point the money ran out
  # still reads as money DENIED rather than money not wanted, which is why the rule exists at all.
  #
  # `[required, 0.to_d].max`, and it is not decoration. `clamp(0, negative)` raises ArgumentError,
  # and a negative ask is reachable: HoldingCalculator#goal_required returns `[rate, remaining].min`,
  # so a savings goal carrying a rule with a negative amount asks for a negative figure and this
  # method takes the whole distribution screen down with a 500. Measured, not assumed —
  # `update_column(:amount, -150)` past the validation reproduces it, and the example in this class's
  # spec pins it. Budget validates the sign, but a validation is an input rule and this is a read
  # path; #allocated_balances defends the same shape one level down for the same reason. Clamping the
  # ASK rather than only the bound also keeps the ROW coherent: a zero ask is rejected above, where a
  # negative one would have rendered "-$150.00 needed" and made #short? read healthy.
  def fill
    remaining = available
    categories.filter_map do |category|
      ask = [ask_calculator_for(category).required, 0.to_d].max
      next if ask.zero?

      row = row_for(category, ask, remaining)
      remaining -= [row.funded, 0.to_d].max
      row
    end
  end

  # One row, funded out of what is left. `needed` is the user's figure where they typed one, so
  # `short` — and with it the cutoff marker, the unfunded total and the leftover — are three views of
  # THIS fill rather than of a proposal the user has already overruled.
  #
  # AN OVERRIDE ABOVE WHAT REMAINS STILL CLAMPS (spec §7.3: "distribution can only hand out cash that
  # exists — already true of the waterfall"). It did not, while overrides were substituted after the
  # fill: an override of $350 against $185 of remaining money wrote $350 and left the root at -$165.
  # The row now reads `$185.00 of $350.00` and says so.
  #
  # A NEGATIVE override bypasses the clamp instead of being floored, and that is a ruling kept alive
  # rather than an oversight: bad input the user has to see, carried through to fail Allocation's
  # `amount > 0` loudly rather than vanishing from a split it was meant to change. `clamp(0,
  # negative)` would raise instead, which is a 500 on a GET. It consumes nothing from `remaining`
  # (see the `max` at the call site) — money cannot flow backwards out of a category that is only
  # ever going to be refused.
  def row_for(category, ask, remaining)
    needed = overrides.fetch(category.id.to_s, ask)
    funded = needed.negative? ? needed : remaining.clamp(0.to_d, needed)

    Row.new(category: category, needed: needed, funded: funded)
  end

  # The plain calculator: what this category holds RIGHT NOW. The sweep is read from here.
  def calculator_for(category)
    (@calculators ||= {})[category.id] ||=
      category.holding_calculator(today: today, terms: ledger.terms_for(category))
  end

  # ONE LEDGER FOR THE WHOLE PROPOSAL — every category this class reads a holding of, plus the root
  # they are funded out of.
  #
  # `user:` IS NOT REDUNDANT WITH THE SET, and the shape it exists for is exactly the one this class
  # meets first: `CategoryLedger#available` is a figure about a USER, and a user whose holder
  # categories are an EMPTY set — every user on their first day, and every user before their first
  # rule — has a real, non-zero available if they have been paid. Read off the categories alone that
  # ledger raises `NoSingleOwner` rather than answering.
  #
  # Lazy like every other memo here, so a proposal built and never read costs nothing.
  #
  # What this class owes AllocationCommitter is about ORDER, not laziness: the committer builds its
  # `#live_proposal` AFTER the deletion, so the proposal it writes is over the post-deletion world.
  #
  # `categories` is read here rather than the scope again, so the ledger and the fill cannot be built
  # over different sets.
  #
  # THIS IS ALSO WHERE A SHARED LEDGER LANDS — see #share_ledger, the only other writer of `@ledger`,
  # and #with_overrides for the rule. `||=` rather than `defined?` because a ledger object is never
  # falsy, so the two forms cost the same and `defined?` would imply an answer this method cannot
  # give.
  def ledger = @ledger ||= CategoryLedger.new(categories, user: user)

  # The post-sweep calculator: what this category would need if its sweep had already happened. The
  # ask is read from here, and from here only.
  #
  # This is the whole reason `net_of_sweep:` exists. #required reads the live balance, and at proposal
  # time the leftover is still in the category — so a swept category would ask for its rule LESS its
  # own leftover, receive that, and start the period short by exactly the amount the sweep took. Not
  # recoverable by adding the sweep back onto #required afterwards: on a mixed category, removing the
  # swept money changes which rules #allocated_balances fills and by how much, so only substituting
  # the balance and re-reading gives the right answer.
  #
  # Unconditional, rather than only for categories that appear in #sweeps. A category with nothing to
  # sweep subtracts `0.to_d` and this is provably the same object's answer as the plain calculator's —
  # so a conditional would buy a handful of queries at the price of a second path through the money.
  #
  # THE SAME `terms:` AS THE PLAIN CALCULATOR, and this is where most of the batching is actually won.
  # A `net_of_sweep` calculator is a HoldingProjection, which builds a plain twin to derive its sweep
  # (see HoldingProjection#twin), so this one object is TWO sets of aggregates — and the projection
  # threads the terms into the twin for exactly that reason.
  def ask_calculator_for(category)
    (@ask_calculators ||= {})[category.id] ||=
      category.holding_calculator(today: today, net_of_sweep: true, terms: ledger.terms_for(category))
  end
end
