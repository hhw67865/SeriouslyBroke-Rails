# frozen_string_literal: true

# ONE MOVE ON THE PURPOSE LEDGER — spec §5's reallocation re-anchored on the two-ledger model, and
# the single-row twin of the distribution screen. READ-ONLY: this presenter writes nothing, and it
# opens no transaction, so unlike DistributionPresenter it may hand live HoldingStatus objects to the
# view. There is no rollback here for a lazily re-executed reader to fall out of.
#
# WHAT THE POOL-ERA TWIN HAD AND THIS DOES NOT (`PoolReallocationPresenter`, deleted by Task 6):
#
#   THE SAME-ACCOUNT RULE. `PoolMovement#crosses_accounts?` and its `must_not_cross_accounts`
#   validation are gone with the concept: an allocation moves nothing physical (§2), so there is no
#   account for a move to cross and no bank for it to move money between. Every one of the user's
#   holder categories is offered, always.
#
#   THE "No account" DESTINATION GROUP, and the grouping itself. Destinations were grouped by the
#   account they sat in, with orphans in a group of their own; there is one root now, so the list is
#   flat and AVAILABLE is simply its first member.
#
# AVAILABLE IS A PARTY, NOT A CONTAINER. It is where a sweep sends a closed category's leftover and
# where a savings withdrawal goes (§3), so it appears on BOTH ends of the screen — as the first
# source and as the first destination. It is not a record, so it is `ROOT` below.
#
# THE INVARIANT is `available + Σ holdings == income − expenses`. A move is `available ↔ category` or
# `category → category`, and neither side of that changes what came in or what went out — which is
# why every figure below is a before/after pair on one party and never a total.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2, §3 and
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4.2, §5
class ReallocationPresenter
  # AVAILABLE, AS ONE END OF A MOVE. A null object rather than a bare `nil`, because `nil` already
  # means "the user has not chosen yet" on this screen and the two must not be the same value: a form
  # with no destination picked and a form asking to withdraw INTO available are different states with
  # different screens.
  #
  # `id` is the string the form round-trips, so a radio and a select option can name the root the way
  # they name a category. It is not a uuid and cannot collide with one.
  Root = Data.define do
    def id = "available"

    def name = "Available"

    def root? = true
  end

  ROOT = Root.new

  # WHY A CATEGORY'S MONEY IS NOT FREE, named rather than left as a bare subtraction. "only $40.00
  # free" and "its own bill is due first" are different sentences and send the user to different
  # places, so the rule that is holding the money travels with the figure.
  #
  # Carries the Budget rather than a string: `HomeHelper#pool_rule_label` is this app's one answer to
  # what a rule is called, and a second one here would drift from every other screen.
  Holder = Data.define(:budget, :allocated, :due_on)

  # A rule whose allocation FELL because of this move — "Maintenance slips to $494 of $800". Read off
  # HoldingCalculator#allocated_balances, the same earliest-due-first fill every other reader in the
  # app uses, so an under-funded rule slips by what it actually loses.
  Slip = Data.define(:budget, :allocated)

  # WHAT THE MOVE COSTS THE SOURCE, before it is committed.
  #
  # `ask_before` and `ask_after` are two REAL RECOMPUTATIONS of HoldingCalculator#required, not a
  # figure derived by dividing the amount moved by something — on the pool-era twin that mistake
  # printed `$206.43` where the truth was `$194.17`.
  #
  # Both are taken with `net_of_sweep: true`, which is the distribution screen's shape
  # (DistributionPresenter#projected_ask) and is load-bearing on exactly one shape: a category whose
  # rate period has closed is going to hand its leftover back and be topped up to its full rate
  # either way, so taking money out of it changes its ask by NOTHING. Read plainly, the screen would
  # print a per-period cost that the next distribution erases. The two readers agree everywhere else
  # — #sweepable_amount is zero unless the period is closed — so the flag only ever removes a lie.
  #
  # `status_after` is nil for the ROOT, which has no status: available is not a category and has no
  # rules to be on track with.
  Damage = Data.define(:balance_before, :balance_after, :ask_before, :ask_after, :slip, :status_after) do
    # Say it only when it is real (spec §5). A rate category's ask and a dateless goal's rate do not
    # move when money leaves, and a screen that prints "+$0.00 a period" on them is the
    # warning-on-a-normal-state that principle 3 forbids.
    def ask_changed? = ask_after != ask_before

    def slipped? = slip.present?
  end

  # One row of the sources list. `requested` is on the row rather than read off the presenter because
  # affordability is a comparison between this party's money and the amount asked for, and splitting
  # the two halves across two objects is how they come to disagree.
  #
  # TWO THRESHOLDS, NOT ONE, and the reasoning is the pool era's, unchanged:
  #
  #   free   = max(holding − reserve, 0), and #allocated_balances fills greedily, so
  #   reserve = min(holding, Σ rule amounts) and free = max(holding − Σ amounts, 0).
  #   A move of `amount ≤ free` leaves the holding ≥ Σ amounts, so EVERY rule still takes its full
  #   amount: no allocation moves, so no rule can slip and #required cannot change. Gating on `free`
  #   would therefore make the damage statement UNREACHABLE.
  #
  #   requested > holding  → DISABLED, with the reason. "Cannot afford it" means the category does
  #                          not hold it, which is also the floor that keeps a move from overdrawing
  #                          the source.
  #   requested > free     → allowed, and the damage statement fires — this is where money that a
  #                          rule was holding gets taken, and stating that cost is what this whole
  #                          screen is for (principle 5).
  #   requested <= free    → allowed, and there is nothing to say beyond the balance arrow.
  #
  # THE ROOT IS ALWAYS IN THE THIRD CASE by construction: available is by definition the money no
  # rule is holding, so `free == holding` and #promised? can never fire on it.
  Candidate = Data.define(
    :category, :root, :holding, :free, :status, :period_closed, :requested, :holder, :damage, :selected
  ) do
    def root? = root

    def id = root? ? ROOT.id : category.id

    def name = root? ? ROOT.name : category.name

    # `holding.positive?` FIRST, so an empty or overspent category is dead even before an amount is
    # typed — with no amount on screen `requested` is zero and would wave it through.
    def affordable? = holding.positive? && requested <= holding

    # The move reaches past what is unpromised and into money a rule is holding. Not "has damage": a
    # dateless savings goal's ask moves on a move well inside its free money, because
    # HoldingCalculator#goal_required reads the balance directly rather than through an allocation.
    def promised? = requested.positive? && requested > free

    def selected? = selected

    # The move pushes this category into a different state — the "Rent still makes Mar 1" half of
    # spec §4.2's fix, said in the app's own row vocabulary rather than in a sentence of its own.
    # False for the ROOT on both sides, which have no state to change.
    def state_changed?
      damage.present? && damage.status_after.present? && status.present? &&
        damage.status_after.state != status.state
    end
  end

  # THE OTHER END. The damage statement is about the source, but a screen that only states costs
  # never says what the move is for, and the destination's status flipping out of `overdue` is the
  # whole reason someone is here. Statuses are nil when the destination is AVAILABLE.
  Gain = Data.define(:category, :root, :balance_before, :balance_after, :status_before, :status_after) do
    def root? = root

    def name = root? ? ROOT.name : category.name

    def state_changed?
      status_before.present? && status_after.present? && status_after.state != status_before.state
    end
  end

  # THE ORDER MONEY IS OFFERED IN, and the ONE place it lives. `[priority, name]` — the order the user
  # ranked their categories in, and the same key `Category.in_fill_order` sorts the waterfall by, so
  # the screen that spends the money and the screen that moves it by hand agree about which category
  # comes first.
  #
  # NO ACCOUNT ARM. The pool-era twin put the account first because it was the buffer; AVAILABLE is
  # the buffer now and it is not a category, so it is placed ahead of this list rather than sorted
  # into it (see #sources).
  #
  # It is a TOTAL order — `Category` validates name uniqueness per user — so it is also the tie-break:
  # priority alone would fall through to database order, which is random UUID bytes deciding which
  # category is offered first.
  #
  # A class method rather than an instance one because it is a property of the category, not of any
  # one proposed move.
  def self.source_order(category) = [category.priority, category.name]

  attr_reader :user, :to_category, :from_category, :amount, :today

  # `to_category` and `from_category` are each a Category, `ROOT`, or nil for "not chosen".
  #
  # `amount` arrives as the form's String and is coerced ONCE, here. nil for a blank box rather than
  # zero, so a submitted blank reads "Amount can't be blank" instead of the arithmetic's "must be
  # greater than 0" — the box is empty, not set to nothing.
  #
  # `ledger:` IS BACK (Task 6), for the reason the pool-era twin took one: HomePresenter builds ONE
  # of these per problem row — see HomePresenter#damage_reader — and each would otherwise open a
  # `CategoryLedger` of its own over the same holder categories, at the same moment, with no `as_of`
  # on either. Four grouped queries per red row on the root route.
  #
  # THE RULE IS `CategoryLedger#for_as_of!`'s, unchanged and asked rather than assumed: a bounded
  # ledger describes a different world, and there is no figure this screen could produce from it that
  # would be right. `nil` is what this class's own ledger carries, so `nil` is what a shared one must.
  #
  # SHARING IS SAFE HERE BECAUSE THIS PRESENTER WRITES NOTHING — a ledger is a snapshot memoised at
  # its first read, so handing one across a write would hand out figures from before it, and both
  # callers of this class render a GET. `AllocationsController#confirmation_for` builds a FRESH
  # ledger after its save for exactly that reason.
  # `rubocop:disable Metrics/ParameterLists` for the sixth KEYWORD, and the cop is counting the wrong
  # thing here: five of these six are the move itself (who, from where, to where, how much, on what
  # day) and the sixth is a COST hint that changes no figure — a ledger reproduces each term line for
  # line, which is the whole of why sharing one is safe. Splitting the move across two objects to
  # satisfy an arity limit would put the amount and the parties in different places, which is exactly
  # how they come to disagree (see Candidate's own note on `requested`).
  # rubocop:disable Metrics/ParameterLists
  def initialize(user:, to_category: nil, from_category: nil, amount: nil, today: Date.current, ledger: nil)
    # rubocop:enable Metrics/ParameterLists
    @user = user
    @to_category = to_category
    @from_category = from_category
    @amount = amount.presence&.to_d
    @today = today
    # CHECKED AT CONSTRUCTION rather than at first read, so a screen holding a ledger from another
    # moment fails before it can render a single figure out of it. `for_as_of!` returns the ledger
    # itself on a match, so this reads as a checked handover rather than as a predicate somebody can
    # forget to branch on.
    @given_ledger = ledger&.for_as_of!(nil)
  end

  # The arithmetic's view of the box: zero when nothing has been typed. Kept apart from #amount so
  # the allocation below can still tell "blank" from "zero".
  def requested = amount || 0.to_d

  def requested? = requested.positive?

  # THE ALLOCATION ITSELF, unsaved. `kind` is not set: `transfer` is the column default, and that is
  # exactly what keeps a reallocation invisible to `Allocation.distributed` — the scope
  # AllocationCommitter deletes when a period is redistributed. A user who moves $50 between
  # categories and then redistributes still has their $50 move.
  #
  # The ROOT becomes a NULL side, which is what NULL MEANS on this table (§2).
  #
  # IT COLLAPSES `nil` AND `ROOT` ONTO THAT SAME NULL, AND IT MUST NOT BE CALLED WITH A `nil` SIDE.
  # This class draws a distinction the ROW cannot carry — `nil` is "the user has not chosen yet",
  # `ROOT` is available — so a half-chosen move built here is a well-formed withdrawal the user never
  # asked for. MEASURED: a POST with a source and no destination saved `Cushion → available` for $300
  # and called it a success. `AllocationsController#missing_side_errors` refuses that shape before it
  # reaches here, and it is above the model deliberately: a NULL side really IS available, so a
  # validation refusing one would refuse every sweep the committer writes.
  def allocation
    Allocation.new(
      from_category: record_of(from_category), to_category: record_of(to_category), amount: amount, date: today
    )
  end

  # Every party the money could come from: AVAILABLE first, then the user's holder categories in the
  # order they ranked them. There is no same-account test — nothing crosses anything (§2).
  #
  # AVAILABLE FIRST for the reason the account came first on the pool-era screen: it is the money no
  # category has claimed (spec §7.1), and it is the source spec §4.2's "this has to come from money
  # you already have" most often means. Idle money costs nothing to move; a savings goal is money the
  # user decided to protect, and richest-first proposed exactly that — a $950 down payment while $330
  # of unallocated money sat unoffered.
  def sources
    return [] if to_category.nil?

    @sources ||= parties.reject { |party| same_party?(party, to_category) }.map { |party| source_for(party) }
  end

  # ONE ROW, for a caller that already knows which source it means. #sources builds a Candidate for
  # every category the user has, and an affordable one costs four calculators over that category.
  #
  # The SAME #candidate_for the list is built from, so this is not a second answer to "what would this
  # move cost".
  def source_for(party) = (@source_for ||= {})[key_for(party)] ||= candidate_for(party)

  def gain
    return nil if to_category.nil? || !requested?

    @gain ||= build_gain
  end

  # The destination select's parties: AVAILABLE, then the holder categories in fill order. FLAT,
  # where the pool era grouped by account — there is one root, so there is nothing to group by, and
  # the "No account" group that named orphans dies with the concept of an orphan.
  def destinations = parties

  # What goes in the amount box: the user's own figure and nothing else. Plain digits, no currency
  # symbol and no delimiter — a `number_field` holding "$1,340.00" reports itself empty to the
  # browser.
  #
  # The nil guard stays HERE and does not move into `DigitsHelper`: nil is meaningful on this screen
  # only (an untouched amount box is empty, not "0.00"), and pushing it down would hand every other
  # consumer a silent nil where a figure belongs.
  def amount_value
    return nil if amount.nil?

    DigitsHelper.digits(amount)
  end

  private

  # AVAILABLE, THEN THE HOLDERS. `Category.in_fill_order` rather than a sort of this class's own: it
  # is `[priority, name]` over holders, which is exactly ::source_order over exactly the categories
  # that can hold money, so the offer list and the waterfall cannot fall into different orders or
  # over different sets.
  def parties = @parties ||= [ROOT, *categories]

  def categories = @categories ||= user.categories.in_fill_order.includes(:budgets).to_a

  def root?(party) = party.is_a?(Root)

  def record_of(party) = root?(party) ? nil : party

  def key_for(party) = root?(party) ? ROOT.id : party.id

  def same_party?(one, other) = key_for(one) == key_for(other)

  # `terms` is read ONCE into a local and handed to all four readers. The destination's aggregates do
  # not depend on which question is being asked of them — before or after, balance or status — so
  # asking the ledger four times would be four identical hashes and four more chances for one of the
  # four to be built without them.
  def build_gain
    return root_gain if root?(to_category)

    category_gain(to_category, ledger.terms_for(to_category))
  end

  def category_gain(category, terms)
    Gain.new(
      category: category,
      root: false,
      balance_before: calculator_for(category).balance,
      balance_after: category.holding_calculator(today: today, pending: incoming, terms: terms).balance,
      status_before: category.status(today: today, terms: terms),
      status_after: category.status(today: today, pending: incoming, terms: terms)
    )
  end

  # MONEY COMING BACK TO THE ROOT — a savings withdrawal (§3), and the one arrival with no status to
  # report: available has no rules, so there is no state for it to flip into.
  def root_gain
    Gain.new(
      category: nil,
      root: true,
      balance_before: available,
      balance_after: available + requested,
      status_before: nil,
      status_after: nil
    )
  end

  def incoming = HoldingProjection::Pending.new(funded: requested, swept: 0.to_d, on: today)

  # THE TWO PENDINGS ARE THE LEDGER THIS MOVE WOULD WRITE, not a signed number, and each side gets the
  # member that matches what actually happens to it.
  #
  # Money OUT is `swept:`, so `Pending#funded_on` stays nil and the source's rate period is not
  # reopened by money leaving it — which is also what the ledger says afterwards, since
  # HoldingCalculator#last_funded_on reads allocations IN alone. Money IN is `funded:` with today's
  # date, which is what the destination's own term will report the moment this saves.
  def outgoing = HoldingProjection::Pending.new(funded: 0.to_d, swept: requested, on: today)

  # BUILT BARE, THEN ASKED. The row is constructed with no holder and no damage, and the two branches
  # below are chosen by asking the ROW ITSELF whether it can make the move — so `Candidate#affordable?`
  # is the ONE spelling of the affordability gate in this file.
  #
  # `Data#with` rather than a second constructor call, so the ten members are written once and a new
  # member cannot be added to one branch and forgotten in the other. It also stops the two readers
  # being computed where nothing renders them: a holder only ever explains a DISABLED row, and damage
  # only ever describes an affordable one.
  def candidate_for(party)
    candidate = root?(party) ? bare_root_candidate : bare_candidate_for(party)

    return candidate.with(holder: holder_for(party)) unless candidate.affordable?
    return candidate unless requested?

    candidate.with(damage: damage_for(party))
  end

  def bare_candidate_for(category)
    calculator = calculator_for(category)

    Candidate.new(
      category: category,
      root: false,
      holding: calculator.balance,
      free: calculator.free_amount,
      status: category.status(today: today, terms: ledger.terms_for(category)),
      # The ` · last period` marker (spec §7.2), and it earns its place on this screen more than on
      # any other: a category whose rate period has closed is about to hand its leftover back to
      # available anyway, so a user reaching for it should know they are taking money that was
      # already on its way out. Plain calculator, which is the only kind that may be asked.
      period_closed: calculator.period_closed?,
      requested: requested,
      holder: nil,
      damage: nil,
      selected: from_category.present? && same_party?(category, from_category)
    )
  end

  # AVAILABLE AS A SOURCE. `free == holding` is not a shortcut: available IS the money no rule is
  # holding, so there is nothing for a reserve to subtract and #promised? can never fire on this row.
  # No status and no closed-period marker, for the same reason — it has no rules to be measured
  # against.
  def bare_root_candidate
    Candidate.new(
      category: nil,
      root: true,
      holding: available,
      free: available,
      status: nil,
      period_closed: false,
      requested: requested,
      holder: nil,
      damage: nil,
      selected: from_category.present? && root?(from_category)
    )
  end

  # What the move costs this source. Only ever called for a row that can make it and an amount that
  # exists — see #candidate_for, which owns both gates.
  def damage_for(party)
    return root_damage if root?(party)

    terms = ledger.terms_for(party)
    after = party.holding_calculator(today: today, pending: outgoing, terms: terms)
    Damage.new(
      balance_before: calculator_for(party).balance,
      balance_after: after.balance,
      ask_before: ask_of(party, HoldingProjection::Pending.none),
      ask_after: ask_of(party, outgoing),
      slip: slip_for(party, after),
      status_after: party.status(today: today, pending: outgoing, terms: terms)
    )
  end

  # THE BALANCE ARROW AND NOTHING ELSE. Available has no rules, so no ask can move and no rule can
  # slip — the three clauses beyond the arrow are all statements about rules, and printing any of
  # them here would be inventing a cost the move does not have.
  def root_damage
    Damage.new(
      balance_before: available,
      balance_after: available - requested,
      ask_before: 0.to_d,
      ask_after: 0.to_d,
      slip: nil,
      status_after: nil
    )
  end

  # HoldingCalculator#required, asked about the same day with the balance this move would leave.
  # `net_of_sweep: true` for the reason on Damage.
  def ask_of(category, pending)
    category.holding_calculator(
      today: today, net_of_sweep: true, pending: pending, terms: ledger.terms_for(category)
    ).required
  end

  # The rule that visibly took the damage: the one whose allocation fell furthest.
  #
  # `allocated_balances` fills earliest-due first, so money leaving starves the rules at the BACK of
  # that order — several can move at once and naming them all is a paragraph. The largest drop is the
  # one a person would point at, and `budget.id` breaks a tie so two equal drops cannot swap between
  # page loads.
  def slip_for(category, after)
    fallen = calculator_for(category).allocated_balances.filter_map do |budget, allocated|
      remaining = after.allocated_balances.fetch(budget, 0.to_d)
      [budget, remaining, allocated - remaining] if remaining < allocated
    end
    budget, remaining, = fallen.min_by { |candidate, _remaining, fell| [-fell, candidate.id] }
    budget && Slip.new(budget: budget, allocated: remaining)
  end

  # The dated rule holding this category's money, earliest due first — "its own bill is due first".
  # nil for the ROOT, which holds money for nothing.
  #
  # Read off `allocated_balances`, which already gives a settled rule nothing, so a paid bill never
  # explains a shortage it is not causing. Rate rules are deliberately absent: they hold money too,
  # and #free_amount already subtracts them, but "only $40.00 free" is the whole of what there is to
  # say about a grocery budget — a date is the part that changes the answer.
  def holder_for(party)
    return nil if root?(party)

    dated = calculator_for(party).allocated_balances.select do |budget, allocated|
      budget.anchor_date.present? && allocated.positive?
    end
    budget, allocated = dated.min_by { |b, _| b.calculator(today: today).due_order }
    return nil if budget.nil?

    Holder.new(budget: budget, allocated: allocated, due_on: budget.calculator(today: today).due_date)
  end

  # MONEY WITH NO JOB YET — the root, read off the same ledger every holding on this screen comes
  # from, so the arrow on the AVAILABLE row and the arrows on the category rows describe one moment.
  def available = @available ||= ledger.available

  # One calculator per category, for the reason HomePresenter#calculator_for gives: #free_amount,
  # #allocated_balances and #balance are all asked of the same category on one render, and each fresh
  # calculator is a set of aggregate queries that memoises nothing for the next one.
  def calculator_for(category)
    (@calculators ||= {})[category.id] ||=
      category.holding_calculator(today: today, terms: ledger.terms_for(category))
  end

  # ONE LEDGER FOR THE SOURCES LIST. #sources builds a Candidate for every holder and an affordable
  # one costs four calculators over that category — the plain one, the one holding the move's
  # `pending`, and the two `net_of_sweep` asks the damage compares, each of which builds a plain twin
  # of its own inside its balance. That is the widest per-category fan-out in the app.
  #
  # Over the SAME set the offer list is built from, plus `user:` so `#available` is answerable for a
  # user with no holders at all — which is every user before their first rule, and exactly the user
  # who would otherwise see this screen raise instead of saying there is nothing to move.
  #
  # A CALLER'S LEDGER WINS, and it was checked at construction — see #initialize.
  def ledger = @ledger ||= @given_ledger || CategoryLedger.new(categories, user: user)
end
