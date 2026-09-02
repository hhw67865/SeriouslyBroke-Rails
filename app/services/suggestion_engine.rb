# frozen_string_literal: true

# THE BOTTOM HALF OF THE BUDGET PAGE (spec §8): four detectors over entry history, run on every
# read. A SUGGESTION IS STILL A DERIVATION — there is no suggestions table and no job, so a rule
# created or a bill that stops paying changes the list on the next page load and nothing has to be
# invalidated.
#
# WHAT CHANGED IS WHETHER ONE CAN BE PUT DOWN (Henry's ruling of 2026-08-20). This header used to
# end "that is also why suggestions cannot be dismissed: a dismissal is state, and the state it
# would hide is drift", and real use answered it: a panel with no way to set a row aside is one
# that gets ignored WHOLE, which hides every kind at once rather than the one the user has already
# decided about. So there IS one table now — `suggestion_dismissals` — and it stores the (kind,
# subject) PAIR a derivation would produce rather than a copy of the suggestion, which is what
# keeps the derivation the only source of the sentence. #hidden is the answer to "where did it go",
# and nothing is dropped silently. The panel's own file carries the full ruling.
#
# The engine WRITES NOTHING. `Σ pools == the bank balance` is untouched here; the risk this class
# carries is different in kind — a wrong threshold nags a user into ignoring the whole panel, and a
# wrong `detail` figure puts a false number on a money screen. Every figure below is therefore
# either an amount observed in the entries or a reading of `Budget#steady_ask`, never a second
# derivation of one the app already computes.
#
# A USER WITH NO DECLARED CADENCE GETS `[]`. Three of the four detectors are windowed in COMPLETE
# PERIODS and `User#period_boundaries` is empty without a cadence, so there are no windows to
# measure in. The dated-bill detector alone could answer without them, and it is suppressed with
# the rest deliberately: the Budget page renders for a user who has not declared a period yet, and
# a panel that proposed a per-period rule to someone with no period would be proposing in units the
# app cannot yet compute.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8, which is the committed record of
# this design and the one a reader can actually open. (It was worked out in
# `.superpowers/sdd/2026-08-16-budget-page/task-6-brief.md` — a gitignored working ledger, named
# here for provenance rather than as somewhere to go.)
class SuggestionEngine
  # ONE SUGGESTION. `subject` is the record the sentence is about — an Item for a dated bill, a
  # Category for a rate, a Budget for drift and a dead rule — `amount` is the figure the sentence
  # leads with, `detail` is the rest of its parts, and `prefill` is the params Task 7's link
  # carries into the existing form.
  Suggestion = Data.define(:kind, :subject, :amount, :detail, :prefill)

  # DETERMINISTIC ORDER, and the rank is spelled rather than derived from the declaration order of
  # anything: a hash whose order decides what a money screen leads with is one refactor away from
  # reordering itself. Dated bills first because a missed dated bill is the failure with a
  # deadline; dead rules last because they cost money quietly rather than urgently.
  KIND_RANK = { dated_bill: 0, rate: 1, drift: 2, dead_rule: 3 }.freeze

  # How many complete periods back the widest detector looks. `#periods` fetches this many once and
  # every detector takes its own tail of the same list, so the boundaries are computed once.
  PERIOD_WINDOW = 6

  RATE_WINDOW_PERIODS = 6
  RATE_MIN_PERIODS = 3
  # How recently a flow must have been seen to still be called one — see #rates' second gate.
  RATE_RECENT_PERIODS = 3
  DRIFT_WINDOW_PERIODS = 4
  DEAD_WINDOW_PERIODS = 3

  # ≥10% AND ≥$10, both. The percentage alone reports a $40 rule that moved $5; the dollar figure
  # alone reports a $2,000 rule that moved 0.6%. A suggestion that fires on a normal state is the
  # noise governing principle 3 exists to forbid.
  DRIFT_MIN_FRACTION = 0.10.to_d
  DRIFT_MIN_AMOUNT = 10.to_d

  BILL_MIN_OCCURRENCES = 2
  # Amounts "within 25% of each other": the largest is at most 1.25× the smallest. A utility bill
  # that swings wider than that is the seasonal case spec §11 puts out of scope.
  BILL_AMOUNT_FACTOR = 1.25.to_d
  BILL_GAP_TOLERANCE_DAYS = 7
  # The average calendar month, used ONLY to guess how many months a gap is; the guess is then
  # checked against real calendar arithmetic (`date >> months`) within ±7 days, so no figure this
  # class reports is ever computed from it.
  DAYS_PER_MONTH = 30.44
  GUESSED_MIN_AMOUNT = 100.to_d
  GUESSED_INTERVAL_MONTHS = 12

  # How far back the entry history is read. A dated bill can be annual, so two occurrences of one
  # need two years; three is one more than that and keeps a very old, long-dead item out of the
  # dated-bill population entirely.
  HISTORY_YEARS = 3

  # How far back #periods looks for boundaries. Seven monthly boundaries span a little over half a
  # year; 400 days clears that for every cadence and costs nothing — `period_boundaries` is pure
  # Ruby and runs no query.
  BOUNDARY_LOOKBACK_DAYS = 400

  attr_reader :user, :today

  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  # ONE HIDDEN SUGGESTION AND THE ROW THAT HIDES IT. The `dismissal` rides along because the panel
  # needs its id for the "Show" button, and looking it up a second time in the view would be a
  # second reader of the pairing this class has already made.
  Hidden = Data.define(:suggestion, :dismissal)

  # WHAT THE PANEL SHOWS: everything the detectors found, minus what this user has put down.
  def suggestions
    @suggestions ||= detected.reject { |suggestion| dismissal_for(suggestion) }
  end

  # WHAT THE PANEL'S FOOT SHOWS, in the same order the rows would have been in. Only suggestions
  # the detectors STILL produce are here: a dismissal whose bill has since been given a rule stops
  # matching anything and is simply not listed — the row is inert rather than dangling, which is
  # why nothing ever has to clean this table up.
  def hidden
    @hidden ||= detected.filter_map do |suggestion|
      dismissal = dismissal_for(suggestion)
      dismissal && Hidden.new(suggestion: suggestion, dismissal: dismissal)
    end
  end

  private

  # EVERY SUGGESTION THE FOUR DETECTORS FOUND, before anything is set aside — the list #suggestions
  # and #hidden are the two halves of. Memoised here rather than in each, so the detectors run once
  # however many of the two the caller asks for.
  def detected
    @detected ||= build_suggestions
  end

  def build_suggestions
    return [] if periods.empty?

    ordered(dated_bills + rates + drifts + dead_rules)
  end

  # THE ROW THAT HIDES THIS SUGGESTION, or nil. `subject.class.name` against `subject_type`: none
  # of the three subject classes is STI, so the two are the same string, and `SuggestionDismissal
  # #key` is the one spelling of the triple on the other side.
  def dismissal_for(suggestion)
    dismissals[[suggestion.kind.to_s, suggestion.subject.class.name, suggestion.subject.id]]
  end

  # THIS USER'S DISMISSALS, keyed by the triple, in ONE query for the whole panel.
  #
  # `user.suggestion_dismissals` AND NOT `SuggestionDismissal.where(kind:, subject:)` per row: a
  # lookup that forgot the owner would let one user's decision hide another user's identical
  # suggestion, which is the thing spec/requests/suggestion_dismissals_spec.rb plants an
  # otherwise-impossible row to pin.
  def dismissals
    @dismissals ||= user.suggestion_dismissals.index_by(&:key)
  end

  # THE SIZE KEY IS PER-PERIOD COST, NOT `amount`. Three of the four kinds already lead with a
  # per-period figure, but a dated bill leads with the BILL — and sorting $1,600 once a year above
  # $1,500 every month puts a $61.54-a-period claim above a $692.31-a-period one, eleven times its
  # size. `detail[:per_period_cost]` is on every kind for exactly this, and it is `fetch`-ed so a
  # kind that ever stopped carrying one raises here rather than silently sorting as nil.
  #
  # `-cost` rather than a reverse sort on a second pass: one comparison, so the three keys cannot
  # disagree about precedence. `subject.id` last, and every subject here is a persisted record read
  # out of the database — nothing in this class compares an id that may be nil.
  def ordered(list)
    list.sort_by do |suggestion|
      [KIND_RANK.fetch(suggestion.kind), -suggestion.detail.fetch(:per_period_cost), suggestion.subject.id]
    end
  end

  # ---------------------------------------------------------------------------------------------
  # Periods
  # ---------------------------------------------------------------------------------------------

  # THE LAST #PERIOD_WINDOW COMPLETE PERIODS, oldest first, as inclusive Date ranges.
  #
  # "Complete" means bounded on BOTH sides by `User#period_boundaries` — the one reader of period
  # edges — so the period containing today is excluded BY CONSTRUCTION rather than by a filter: the
  # boundaries stop at `today`, and `each_cons(2)` can only emit a period that has a boundary on
  # both sides of it. A `select { period.last < today }` on top was written first and then measured
  # to be dead — it never removed a period on any cadence — so it is not here pretending to be the
  # guard. A half-elapsed period counted as a whole one would halve every average this class
  # computes, which is drift reported on a rule that is exactly right.
  def periods
    @periods ||= begin
      boundaries = user.period_boundaries(from: today - BOUNDARY_LOOKBACK_DAYS, to: today)

      boundaries
        .each_cons(2)
        .map { |opened_on, next_boundary| opened_on..(next_boundary - 1) }
        .last(PERIOD_WINDOW)
    end
  end

  # A period as the TIMESTAMP range to query with. `entries.date` is a datetime column, so a range
  # of bare Dates would end the last day at its own midnight and drop every entry recorded during
  # it. This is `User#period_datetimes_containing`'s widening, applied to a period this class
  # already holds rather than by re-deriving the period from a date inside it.
  def datetimes_over(window)
    window.first.first.beginning_of_day..window.last.last.end_of_day
  end

  # Which of `window`'s periods a date falls in, or nil for a date outside all of them.
  def period_index(window, date)
    window.index { |period| period.cover?(date) }
  end

  # ---------------------------------------------------------------------------------------------
  # Shared reads — one query each, for every detector that needs them
  # ---------------------------------------------------------------------------------------------

  # EVERY EXPENSE CATEGORY THIS USER OWNS, and it is loaded before the items rather than preloaded
  # off them because THREE separate things are questions about categories rather than about items:
  # the rate detector's population, the name the bill sentence carries, and whether accepting a
  # proposal would start this category holding money at all.
  #
  # `includes(:pool)` IS GONE WITH THE ENVELOPE HALF (two-ledger spec §3). It was there so a
  # proposal could ask whether the category's pool was an account and therefore un-reusable as an
  # envelope; there are no envelopes to reuse — the category IS the thing that holds the money — so
  # the preload paid for a link nothing here reads.
  def expense_categories
    @expense_categories ||= user.categories.expenses.to_a
  end

  def categories_by_id = @categories_by_id ||= expense_categories.index_by(&:id)

  def category_for(item) = categories_by_id.fetch(item.category_id)

  # Every expense item this user owns. Selected by the category ids already in memory rather than
  # through `Item.expenses`' join, so this adds no second reading of what an expense is and no
  # second query for the categories it would join to.
  def expense_items
    @expense_items ||= Item.where(category_id: categories_by_id.keys).to_a
  end

  # THE WHOLE EXPENSE HISTORY, as `[item_id, amount, date]` triples — one query serving the
  # dated-bill detector (which needs the shape of each item's occurrences), the rate detector
  # (which rolls the same rows up by category and period) and the dead-rule detector (which needs
  # to know when an item last had one). Plucked rather than instantiated: nothing here reads an
  # Entry's behaviour, only three of its columns.
  def entry_rows
    @entry_rows ||= Entry.expenses
      .where(categories: { user_id: user.id })
      .where(date: (today - HISTORY_YEARS.years).beginning_of_day..)
      .order(:date)
      .pluck(:item_id, :amount, :date)
  end

  # `[amount, date]` pairs per item, ascending by date — `entry_rows` is ordered, and `group_by`
  # preserves it.
  def entries_by_item
    @entries_by_item ||= entry_rows
      .group_by(&:first)
      .transform_values { |rows| rows.map { |(_id, amount, date)| [amount.to_d, date.to_date] } }
  end

  # Both owner lanes, through the one reader of "a user's rules". Preloaded because every detector
  # below asks a rule for its item or its category.
  #
  # `:pool` LEFT THE PRELOAD and `:category` took its place: a rule belongs to the category that
  # holds the money (two-ledger spec §3), and the two detectors that name a rule's owner —
  # drift's sentence and a dead rule's — read the category now.
  def budgets
    @budgets ||= Budget.for_user(user).includes(:item, :category).to_a
  end

  # The items that already carry a rule of their own. Dated-bill skips them (proposing a rule for
  # an item that has one is proposing a duplicate) and drift subtracts their entries from the
  # category's spend (amendment A).
  def item_backed_ids = @item_backed_ids ||= budgets.filter_map(&:item_id).to_set

  # ---------------------------------------------------------------------------------------------
  # Detector 1 — a dated bill nobody has written a rule for
  # ---------------------------------------------------------------------------------------------

  # TWO OR MORE OCCURRENCES OF SIMILAR SIZE, A WHOLE NUMBER OF MONTHS APART, ON AN ITEM WITH NO
  # RULE — or one occurrence big enough to be a bill, whose interval is then a GUESS and is said to
  # be one. The amount is the HIGHEST observed, per spec §8: a rule that over-reserves leaves money
  # in an envelope, and a rule that under-reserves leaves a bill unpaid.
  # Memoised because the rate detector reads it too (see #category_spend_by_period), and a second
  # pass over the whole entry history to answer the same question would be paid for nothing.
  def dated_bills
    @dated_bills ||= expense_items.filter_map do |item|
      next if item_backed_ids.include?(item.id)

      occurrences = entries_by_item[item.id]
      next if occurrences.blank?

      shape = bill_shape(occurrences)
      shape && dated_bill_suggestion(item, shape)
    end
  end

  # nil unless the occurrences look like a bill. Two shapes, and the second is deliberately narrow:
  # a single small purchase is not a bill, so only one of $100 or more — on an item with NOTHING
  # else against it — is proposed at all, and it is proposed as a guess.
  def bill_shape(occurrences)
    amounts = occurrences.map(&:first)
    dates = occurrences.map(&:last)

    return single_occurrence_shape(amounts, dates) if occurrences.size < BILL_MIN_OCCURRENCES
    return nil unless amounts.max <= amounts.min * BILL_AMOUNT_FACTOR

    gaps = whole_month_gaps(dates)
    return nil if gaps.blank?

    { amount: amounts.max, interval_months: median(gaps), last_seen_on: dates.last, occurrences: occurrences.size, guessed: false }
  end

  def single_occurrence_shape(amounts, dates)
    return nil if amounts.first < GUESSED_MIN_AMOUNT

    { amount: amounts.first, interval_months: GUESSED_INTERVAL_MONTHS, last_seen_on: dates.first, occurrences: 1, guessed: true }
  end

  # The months between each pair of consecutive occurrences, or nil if ANY gap is not a whole
  # number of months. `(earlier >> months)` is real calendar arithmetic — the 30.44 above only
  # picks which month to check — so a bill paid on the 31st and then on the 30th of a short month
  # is one month apart rather than 0.98 of one.
  def whole_month_gaps(dates)
    gaps = dates.each_cons(2).map { |earlier, later| whole_months_between(earlier, later) }

    gaps.all? ? gaps : nil
  end

  def whole_months_between(earlier, later)
    months = ((later - earlier).to_i / DAYS_PER_MONTH).round
    return nil if months < 1
    return nil if ((earlier >> months) - later).abs > BILL_GAP_TOLERANCE_DAYS

    months
  end

  def median(values)
    sorted = values.sort
    middle = sorted.size / 2

    sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
  end

  # NEXT DUE IS ROLLED FORWARD PAST TODAY, and this is a correction to the brief's "last occurrence
  # + interval" — see the task report. A bill last paid on the 2nd of last month, one month apart,
  # is next due on the 2nd of THIS month, which for most of the month is a date in the past: the
  # panel would propose "next due Aug 2" on Aug 16.
  #
  # EVERY CANDIDATE IS `>>`-ed FROM `last_seen_on` ONCE, never from the previous candidate, and that
  # is not a refactor: `Date#>>` CLAMPS to the end of a short month and the clamp is permanent if it
  # is fed back in. Rolling Jan 31 forward month by month gives Feb 28 → Mar 28 → Apr 28, and the
  # bill is paid on the 30th; anchoring each step on the source gives Jan 31 >> 3 = Apr 30, which is
  # the day the bill actually falls on. The bug was invisible to a Dec → Mar fixture, where no month
  # is short enough to clamp.
  def next_due_on(last_seen_on, interval_months)
    steps = 1
    steps += 1 while (last_seen_on >> (interval_months * steps)) < today

    last_seen_on >> (interval_months * steps)
  end

  def dated_bill_suggestion(item, shape)
    due_on = next_due_on(shape[:last_seen_on], shape[:interval_months])
    category = category_for(item)

    Suggestion.new(
      kind: :dated_bill,
      subject: item,
      amount: shape[:amount],
      detail: bill_detail(shape, due_on, category),
      prefill: { budget: bill_rule(shape, due_on, item, category) }
    )
  end

  def bill_detail(shape, due_on, category)
    shape.except(:amount).merge(
      due_on: due_on,
      category_name: category.name,
      starts_holding: starts_holding?(category),
      per_period_cost: bill_per_period_cost(shape)
    )
  end

  # THE WHOLE RULE, AND THE OWNER IS ONE OF ITS FIELDS. Every key here is a `budgets` column and a
  # permitted parameter of `BudgetsController::BUDGET_FIELDS`, which is what lets the accept link
  # be `new_budget_path(budget: …)` with nothing renamed on the way.
  def bill_rule(shape, due_on, item, category)
    {
      amount: shape[:amount],
      basis: "monthly",
      interval_months: shape[:interval_months],
      anchor_date: due_on,
      item_id: item.id,
      category_id: category.id
    }
  end

  # WHAT A PROPOSED BILL WOULD COST A PERIOD, through `Budget#steady_ask` on an UNSAVED rule of the
  # exact shape being proposed — the app's one normaliser, asked about a rule that does not exist
  # yet, rather than a fifth spelling of `amount * 12 / (periods_per_year * interval)` here. It
  # touches no database: `#cadence` reads three columns off the in-memory record and the monthly
  # branch divides.
  #
  # It is what the list is ORDERED by (see #ordered) and it is in `detail` because Task 7's sentence
  # needs it for the same reason: a $1,600 bill once a year costs $61.54 a period and a $1,500 bill
  # every month costs $692.31, and the raw amounts put them in the wrong order by a factor of eleven.
  def bill_per_period_cost(shape)
    Budget.new(amount: shape[:amount], basis: :monthly, interval_months: shape[:interval_months])
      .steady_ask(user, today: today)
  end

  # WOULD ACCEPTING THIS START THE CATEGORY HOLDING MONEY? — the one thing left of what used to be
  # `#envelope_half`, and the whole of what the panel's effect clause now has to say.
  #
  # THE ENVELOPE HALF IS DELETED (two-ledger spec §3/§5). It carried a proposed `pool` (name, type,
  # account) or a `pool_id` to reuse, plus the `category_id` to be RE-POINTED at it, because a rule
  # could only be owned by an envelope and money only reached one through the category's `pool_id`.
  # There is no envelope: `budgets.category_id` is the owner, the category holds the money, and
  # accepting writes a rule and stamps `funded_since` (`BudgetProposal`). Nothing is minted and
  # nothing is re-pointed, so the whole three-branch reuse cascade — and the "shared envelope"
  # consequence that made two bills in one category a design decision — is simply the ordinary case:
  # two rules on one category, which is what one category, one budget line always meant.
  #
  # `funded_since` IS THE QUESTION because it is what `Category#holder?` reads and what the write
  # stamps. A category already holding money is not started by this acceptance; one that is not is,
  # and the row says so before the click because it changes which side of the start-date rule every
  # future entry falls on.
  def starts_holding?(category) = category.funded_since.nil?

  # ---------------------------------------------------------------------------------------------
  # Detector 2 — a category that behaves like a rate and is funded by nothing
  # ---------------------------------------------------------------------------------------------

  # A CATEGORY THAT HOLDS NOTHING is the population (two-ledger spec §3/§4), and that is the
  # sentence's own reason: nothing holds this money, so it comes out of what is available.
  #
  # THE POPULATION IS `funded_since IS NULL` — `Category#holder?` inverted — WHERE IT USED TO BE
  # `buffer_funded?`. The two name the same users' same categories through two different models:
  # under the pool layer, "unbudgeted" meant the category pointed at an ACCOUNT rather than at an
  # envelope, and every spelling of it (`budgetable?`, then `buffer_funded?`) was really asking
  # whether anything reserved this money. It asks that directly now. `CategoryLedger
  # ::ENTRY_CATEGORY_ID` sends an unfunded category's every entry to AVAILABLE, so the detector's
  # sentence — this spending comes out of what's available — is not a paraphrase of the population
  # but a literal reading of it.
  #
  # THE MEAN, NOT THE MAXIMUM. Highest-observed is right for a bill, which must be paid in full or
  # not at all; a rate is a flow, and reserving every grocery category's worst fortnight would
  # over-reserve every one of them forever.
  # TWO GATES, and the second is a ruling of this task's fix round. `≥3 of the last 6` alone says
  # only that the category was once a flow: a subscription cancelled three periods ago passes it,
  # and the divisor below — which anchors on FIRST appearance and never on last — then proposes the
  # dead flow as ongoing at half its old rate. So it must also have appeared at least once in the
  # most recent #RATE_RECENT_PERIODS. A rate is a claim about what will happen next period, and
  # nothing that stopped supports one.
  def rates
    window = periods.last(RATE_WINDOW_PERIODS)
    totals, first_seen = category_history(window, exclude: proposed_bill_item_ids)

    unfunded_categories.filter_map do |category|
      # `fetch`, not `[]`: `#category_history` returns a Hash with a default PROC, and `[]` on a
      # missing key would write an empty bucket into it mid-iteration.
      present = totals.fetch(category.id, {}).reject { |_index, total| total.zero? }
      next if present.size < RATE_MIN_PERIODS
      next if present.keys.max < window.size - RATE_RECENT_PERIODS

      rate_suggestion(category, present, window, first_seen.fetch(category.id))
    end
  end

  # The categories that hold nothing, read off the column rather than through a predicate: the
  # positive spelling is `Category#holder?` (`expense? && funded_since.present?`) and every category
  # here is already an expense by construction, so the negation of the half that is left is the
  # whole of the question. Costs no query — the categories are in memory above.
  def unfunded_categories
    @unfunded_categories ||= expense_categories.select { |category| category.funded_since.nil? }.sort_by(&:id)
  end

  # `[{ category_id => { period_index => total } }, { category_id => earliest entry date }]`, rolled
  # up in Ruby off the ONE history query rather than fetched per period or per category.
  #
  # THE SECOND HALF IS A REAL ENTRY DATE. `first_seen_on` used to be the first measured period's
  # START, which is a date no entry supports: a category first spent on the 9th was reported as
  # first seen on the 2nd, and Task 7 would have rendered that claim. The period count is already in
  # `periods_measured`; this is the day something actually happened.
  #
  # `exclude:` IS THE DATED BILLS, and it is a correction to the brief — the measurement is in the
  # task report. Rent is $1,500 on the 1st of every month and it lives in a buffer-funded category, so
  # verbatim the demo proposed a $1,500 dated bill for Rent AND a "rate" for Housing whose average
  # was mostly that same rent: the same dollars, proposed twice, on a money screen. A bill is not a
  # rate — it is the shape the OTHER detector exists for — so its payments are not part of the flow
  # this one measures.
  def category_history(window, exclude:)
    totals = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
    first_seen = {}

    windowed_rows(window, exclude).each do |category_id, amount, on, index|
      totals[category_id][index] += amount
      first_seen[category_id] = earlier_of(first_seen[category_id], on)
    end

    [totals, first_seen]
  end

  # The history rows that fall inside `window` and are not a proposed bill, re-keyed onto the
  # category and the period they belong to. Separated from the roll-up above so that "which rows
  # count" and "what they add up to" are two readable steps rather than one loop doing both.
  def windowed_rows(window, exclude)
    entry_rows.filter_map do |item_id, amount, date|
      next if exclude.include?(item_id)

      on = date.to_date
      index = period_index(window, on)
      next unless index

      [category_of.fetch(item_id), amount.to_d, on, index]
    end
  end

  def earlier_of(known, candidate) = known.nil? || candidate < known ? candidate : known

  def proposed_bill_item_ids = @proposed_bill_item_ids ||= dated_bills.to_set { |suggestion| suggestion.subject.id }

  def category_of = @category_of ||= expense_items.to_h { |item| [item.id, item.category_id] }

  # THE DIVISOR IS PERIODS LIVED THROUGH, NOT PERIODS IT APPEARED IN — a correction to the brief,
  # and it is the mixed-unit trap in per-period clothing. "Total ÷ periods it appeared in" answers
  # *how much when it happens*, which is a per-OCCURRENCE figure; a rate rule reserves money EVERY
  # period, so a per-occurrence figure proposed as a rate over-reserves by exactly
  # window ÷ appearances. Measured on the demo: Housing appeared in 3 of 6 biweekly periods (rent
  # lands monthly) and was proposed at **$1,061 a period** against a real cost of about $700 — the
  # same doubling `steady_ask` exists to prevent, made in the proposal instead of in the rule.
  #
  # The span runs from the FIRST period it appeared in, not from the start of the window, so a
  # category that only started three periods ago is not halved for the three periods before it
  # existed. It can never be smaller than the appearance count, so this never divides by less than
  # the brief's own divisor either.
  def periods_measured(present, window) = window.size - present.keys.min

  def rate_suggestion(category, present, window, first_seen_on)
    observed_total = present.values.sum(0.to_d)
    span = periods_measured(present, window)
    # `.ceil` on a BigDecimal answers an Integer, and an Integer amount is the money-type leak this
    # branch has found at every empty or rounded figure — `.to_d` puts it back on the money type
    # every other amount in this class carries.
    amount = (observed_total / span).ceil.to_d

    Suggestion.new(
      kind: :rate,
      subject: category,
      amount: amount,
      detail: {
        periods_present: present.size,
        periods_measured: span,
        periods_window: window.size,
        first_seen_on: first_seen_on,
        observed_total: observed_total,
        per_period_cost: amount,
        # ALWAYS TRUE HERE, and stated rather than inferred: this detector's population IS the
        # categories with no `funded_since`, so accepting one always starts it holding. The key is
        # carried anyway so the panel's effect clause reads one member on both proposing kinds
        # rather than branching on the kind to decide which question to ask.
        starts_holding: starts_holding?(category),
        guessed: false
      },
      prefill: { budget: { amount: amount, basis: "per_period", category_id: category.id } }
    )
  end

  # ---------------------------------------------------------------------------------------------
  # Detector 3 — an existing rate rule that no longer matches the spending
  # ---------------------------------------------------------------------------------------------

  # DRIFT MEASURES THE RULE'S OWN LANE (amendment A). A category carrying a rate rule and an
  # item-backed bill would otherwise count the bill's payments as rate spend and report drift on a
  # rule that is exactly right, so the observed figure is the expense entries draining the category
  # MINUS the entries on items that carry their own rule.
  #
  # THE BASELINE IS `Budget#steady_ask` — Task 4's reader, not a re-derivation. Re-deriving "what
  # this rule costs a period" here would give the app a second normaliser one task after it was
  # collapsed to one, and the two would disagree for exactly the biweekly monthly-rule case that
  # collapse exists to get right.
  #
  # FOUR COMPLETE PERIODS ARE REQUIRED, not "up to four": an average over the two periods a new
  # user has is a sample, and reporting it as drift would tell them to rewrite a rule on a
  # fortnight's evidence.
  def drifts
    window = periods.last(DRIFT_WINDOW_PERIODS)
    return [] if window.size < DRIFT_WINDOW_PERIODS

    rules = attributable_rate_rules
    return [] if rules.empty?

    spend = category_spend(rules.map(&:category_id), window)
    rules.filter_map { |rule| drift_suggestion(rule, spend.fetch(rule.category_id, 0.to_d), window) }
  end

  # A RATE RULE IS ONE WITH NO DUE DATE: `per_period`, or the anchorless monthly rule that
  # `Budget#shape_must_be_valid` pins to `interval_months == 1`. Both are flows, both normalise
  # through `steady_ask`, and a screen that reported drift on only one of the two spellings would
  # be silent on half the rate rules the app can store.
  #
  # A CATEGORY-OWNED RULE, AND THE FILTER IS BACK FOR THE LENGTH OF THE BRANCH (two-ledger spec §3,
  # Task 5 — deleted by Task 8 with `budgets.pool_id`). `Budget.for_user` still spans both owner
  # lanes, so `#budgets` can hand back a rule written before the cutover that names only a pool;
  # the observed figure below is "what drained this CATEGORY", which such a rule has none of, and
  # grouping it under a nil key would attribute every pool-only rate rule's silence to one another.
  #
  # A CATEGORY CARRYING MORE THAN ONE RATE RULE IS SKIPPED OUTRIGHT: its spend cannot be attributed
  # between them, and a suggestion that guessed the split would put a figure on a money screen that
  # no entry supports.
  def attributable_rate_rules
    rate_rules = budgets.select { |budget| budget.category_id.present? && rate_shape?(budget) }

    rate_rules.group_by(&:category_id).filter_map { |_category_id, rules| rules.first if rules.one? }
  end

  # ITEM-LESS, and that condition is amendment A's own consequence rather than an extra filter. The
  # observed figure EXCLUDES entries on items that carry a rule; if the rate rule under examination
  # is itself item-backed, the exclusion subtracts its own lane. Where the category holds nothing else,
  # the figure is $0 and the zero-guard hides drift that is genuinely there; where it holds
  # something else, the figure is built entirely from dollars this rule does not cover. Both are a
  # number on a money screen that describes different money from the sentence around it. An
  # item-backed rule is detector 4's subject, not this one's.
  def rate_shape?(budget)
    budget.anchor_date.blank? && budget.item_id.blank? && [:per_period, :monthly].include?(budget.cadence)
  end

  # `{ category_id => total }` over the drift window, in one query for every category at once.
  #
  # `CategoryLedger::ENTRY_CATEGORY_ID` is reused rather than restated, and the objection is exactly
  # the one its pool-era predecessor answered: "which category does this entry drain" already has
  # one SQL form in this app — the start-date rule, `funded_since` compared in the owner's own
  # calendar day — and a second spelling of it is how a suggestion and a balance come to describe
  # different money. An UNFUNDED category answers NULL there and so contributes nothing here, which
  # is why #drift_suggestion's zero-guard asks `holder?` rather than reading the silence as spend.
  #
  # `ENTRY_CATEGORY_JOINS` travels with the constant (its contract): the expression reads the
  # category's own user for the timezone, so a reader that took the SQL without the join would not
  # compile — and one that took it with a DIFFERENT join would be the second spelling this comment
  # exists to forbid.
  def category_spend(category_ids, window)
    Entry.expenses
      .joins(*CategoryLedger::ENTRY_CATEGORY_JOINS)
      .where(categories: { user_id: user.id })
      .where(date: datetimes_over(window))
      .where.not(item_id: item_backed_ids.to_a)
      .where("#{CategoryLedger::ENTRY_CATEGORY_ID} IN (:ids)", ids: category_ids)
      .group(CategoryLedger::ENTRY_CATEGORY_ID)
      .sum(:amount)
      .transform_values(&:to_d)
  end

  # NO SPEND AND NO LANE IS NOT DRIFT; NO SPEND WITH A LANE IS THE STARKEST DRIFT THERE IS.
  #
  # The first half is the correction the demo forced, RE-ANCHORED (two-ledger spec §4). It used to
  # ask whether any category pointed at the rule's envelope: five demo envelopes had none, recorded
  # no spending by construction, and reading that silence as "you spend nothing, cut the rule to
  # zero" told the demo user to zero their $400 grocery rule. The category IS the lane now, so the
  # question that survives is whether the lane can record anything at all — `Category#holder?`,
  # which is exactly what `CategoryLedger::ENTRY_CATEGORY_ID` gates on. An unfunded category sends
  # every one of its entries to AVAILABLE, so its $0.00 is a fact about the start-date rule and not
  # about the user's spending.
  #
  # The second half is the lane that silence used to swallow, and it is the more valuable sentence.
  # The category HOLDS money, four complete periods have passed, and nothing was spent: "Groceries
  # has averaged $0.00 for 4 periods, your rule says $400" is spec §8's drift sentence with the
  # starkest figure it can carry. Detector 4 cannot say it — that one is item-backed rules only — so
  # without this the funded category that quietly stopped has no owner at all.
  def drift_suggestion(rule, observed_total, window)
    return nil if observed_total.zero? && !rule.category.holder?

    rule_amount = rule.steady_ask(user, today: today)
    observed = (observed_total / window.size).round(2)
    gap = (observed - rule_amount).abs
    return nil if gap < DRIFT_MIN_AMOUNT || gap < rule_amount * DRIFT_MIN_FRACTION

    Suggestion.new(
      kind: :drift,
      subject: rule,
      amount: observed,
      detail: drift_detail(rule, rule_amount, observed, window),
      prefill: { id: rule.id, budget: { amount: rule_unit_amount(rule, observed) } }
    )
  end

  def drift_detail(rule, rule_amount, observed, window)
    {
      rule_amount: rule_amount,
      observed: observed,
      periods: window.size,
      direction: observed > rule_amount ? :up : :down,
      category_name: rule.category.name,
      basis: rule.basis,
      per_period_cost: observed,
      guessed: false
    }
  end

  # THE FORM'S FIELD IS IN THE RULE'S OWN UNIT, and getting there means INVERTING `steady_ask`.
  #
  # Everything this class reports is per-period, because that is the unit a user's money leaves in.
  # `budgets.amount` is not: on the anchorless monthly rule — which #rate_shape? admits deliberately
  # — it is a MONTHLY figure, and `steady_ask` is what divides it down. Writing a per-period observed
  # figure straight into that column is the mixed-unit trap in the half that WRITES: a $260/month
  # rule reads $120 a period, an observed $200 says raise it, and `amount: 200` in a monthly field
  # is $92.31 a period — LESS than the figure the user was just told was too low, on a suggestion
  # that asked them to raise it. The inverse of `amount * 12 / (periods_per_year * interval)`.
  #
  # It cannot be read off `steady_ask` — no reader inverts itself — so it is spelled here, once, and
  # the spec pins it by round-tripping the answer back through `steady_ask` as well as by literal.
  # `detail[:basis]` carries the unit so Task 7 can label the field rather than guess.
  def rule_unit_amount(rule, per_period)
    return per_period if rule.basis_per_period?

    (per_period * user.periods_per_year * (rule.interval_months || 1) / 12).round(2)
  end

  # ---------------------------------------------------------------------------------------------
  # Detector 4 — a rule still funding something that stopped
  # ---------------------------------------------------------------------------------------------

  # ITEM-BACKED RULES ONLY, because an item is what makes a rule payable and therefore what can
  # stop. AN ITEM THAT NEVER HAD AN ENTRY IS NEW, NOT DEAD: a rule written today for a bill that
  # has not arrived yet is the ordinary way one is created, and reporting it as dead would fire on
  # every rule the panel's own dated-bill suggestion just produced.
  def dead_rules
    window = periods.last(DEAD_WINDOW_PERIODS)
    return [] if window.size < DEAD_WINDOW_PERIODS

    budgets.filter_map do |rule|
      next if rule.item_id.blank?

      occurrences = entries_by_item[rule.item_id]
      next if occurrences.blank?

      dead_rule_suggestion(rule, occurrences, window)
    end
  end

  def dead_rule_suggestion(rule, occurrences, window)
    last_seen_on = occurrences.last.last
    return nil if last_seen_on >= window.first.first

    # WHAT IT COSTS A PERIOD, not what the rule says: a $1,200 six-monthly premium and a $200
    # per-period rate are the same sentence to a user only once both are stated in the unit the
    # money actually leaves in. `steady_ask` again, for the same reason drift uses it.
    per_period = rule.steady_ask(user, today: today)

    Suggestion.new(
      kind: :dead_rule,
      subject: rule,
      amount: per_period,
      detail: {
        last_seen_on: last_seen_on,
        periods_empty: window.size,
        rule_amount: rule.amount.to_d,
        item_name: rule.item.name,
        # `&.`, AND IT IS TRANSITIONAL RATHER THAN DEFENSIVE (Task 8 deletes the nil): `Budget
        # .for_user` still spans both owner lanes, so a rule written before the cutover names only a
        # pool and has no category to be filled from. The row's own partial prints the clause only
        # where there is one.
        category_name: rule.category&.name,
        per_period_cost: per_period,
        guessed: false
      },
      prefill: { id: rule.id }
    )
  end
end
