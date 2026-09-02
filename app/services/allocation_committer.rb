# frozen_string_literal: true

# Turns a proposal into allocations. Sweeps first (category -> available), then allocations
# (available -> category), all inside one transaction so a failure leaves the ledger exactly as it
# was. This is the purpose ledger's only writer besides entries, and the only invariant that matters
# is that it never creates or destroys any money: every row moves money between the user's own root
# and their own categories, so `available + Σ holdings == income − expenses` before and after.
#
# ONE SPLIT PER PERIOD PER USER (two-ledger spec §2). There is no account here and no per-account
# scoping left in #previous_distribution: the purpose ledger has one root, so "this period's
# distribution" is a fact about the user rather than about one of their bank accounts.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2, and
# docs/superpowers/plans/2026-08-16-distribution.md Task 3, spec §5
class AllocationCommitter
  # One shape for both outcomes, so a caller cannot read a success off a failure by accident: a
  # failure carries no allocations and a success carries no errors, and every reader answers on
  # either. `0.to_d` seeds both totals — an empty commit is the emptiest possible sum and exactly
  # where a bare Integer 0 would leak out into the confirmation flash and the errors band the
  # distributions controller renders beside it.
  Result = Data.define(:allocations, :errors) do
    def success? = errors.empty?

    def allocated = total_for(:kind_allocation?)

    def swept = total_for(:kind_sweep?)

    # HOW MANY CATEGORIES RECEIVED MONEY, which is not `allocations.size`: the sweeps in that list
    # came the other way, out of categories and back to available, so counting them would tell the
    # user they funded categories they took money back from. Named for the count it is, beside two
    # readers that are amounts.
    def categories_funded = allocations.count(&:kind_allocation?)

    private

    def total_for(predicate) = allocations.select(&predicate).sum(0.to_d, &:amount)
  end

  attr_reader :proposal

  # `proposal` names the user, the day being distributed AND THE USER'S OVERRIDES — the context the
  # caller already holds. The FIGURES are re-derived (see #live_proposal); a proposal that was
  # rendered and then confirmed is a snapshot, and this class writes against the ledger.
  #
  # THIS CLASS TAKES NO OVERRIDES. It used to accept an `overrides:` keyword and substitute those
  # figures onto the finished rows, which made it the second place a split was decided:
  # AllocationCalculator#fill computed one and this class quietly wrote another. The cost was not
  # theoretical — substituting after the fill means money freed by cutting a high row can never reach
  # the category below it, because the waterfall is already over. The override lives on the
  # calculator and is applied inside the fill, so this class writes exactly what the proposal says
  # and has nothing left to disagree with the screen about.
  def initialize(proposal)
    @proposal = proposal
  end

  # ONE transaction, and the sweeps are what make it load-bearing: they are written first, so a bad
  # allocation has to take an already-saved sweep back out with it. The DELETION is inside it too,
  # and that is the half with no compensating write to give it away: hoisted out, a failed re-run
  # destroys the previous split, writes nothing in its place and still reports `success? == false`.
  #
  # `requires_new: true`, and it is not decoration. A `transaction` block inside an already open
  # transaction opens no savepoint by default, so `ActiveRecord::Rollback` is swallowed and the OUTER
  # transaction commits: the sweeps and the valid allocations land, the bad line does not, and this
  # class reports a failure over a half-written split — the one outcome it exists to prevent.
  #
  # Every line is attempted rather than stopping at the first bad one, so a form comes back with all
  # of its bad lines marked at once.
  #
  # The memos are reset here rather than in #initialize, so a second #call replaces its own split
  # from a proposal built against the ledger as it stands. Left memoised, the second call would
  # delete this period's rows and re-commit the FIRST call's snapshot — exactly the staleness this
  # class exists to defend against.
  #
  # `user.lock!` IS THE FIRST STATEMENT INSIDE THE TRANSACTION, before the deletion and therefore
  # before anything is read, and it is what makes the split safe against a SECOND CONFIRM rather than
  # only against a stale one.
  #
  # THE USER'S OWN ROW IS THE SERIALISATION POINT, where the pool era locked the ACCOUNT. That is
  # the model change and not a weakening: there was one distribution per account, and there is now
  # one per user, so the row that has to be held is the one every split of this period contends for.
  # It is also the row every write here already touches — `Allocation belongs_to :from_category /
  # :to_category, touch: true` and `Category belongs_to :user, touch: true` — so the lock and the
  # cascade name the same row and cannot deadlock against each other.
  #
  # Every figure below is re-derived inside this transaction, which is strong against staleness and
  # says nothing about concurrency: under READ COMMITTED two overlapping POSTs on a never-distributed
  # period both find nothing to delete, both read unfunded categories, and both write a full split.
  # MEASURED on the pool-era twin, with the lock removed and the two commits interleaved by hand (see
  # the racing example in this class's spec): Groceries ended at $715 against a $400 rule and the
  # root at -$130. Conservation is not the property that breaks — the partition still held — while
  # the root was over-allocated by $130, which is the state spec §7.3 exists to forbid.
  #
  # The confirm path is deliberately built to work with JavaScript off (that is why the CSRF token
  # rides on the button's own name/value), so Turbo disabling the submitter is not the defence: with
  # JS off a double-click submits twice, and two tabs reach it either way.
  #
  # It also serialises the distribution SCREEN against the write, for the same reason the account
  # lock did: the presenter's delete-compute-rollback takes this lock first, so a commit arriving
  # mid-render waits for it instead of reading around it.
  #
  # `lock!` rather than `with_lock`, because the transaction is already open and the rollback
  # semantics above depend on its being THIS one.
  def call
    @errors = []
    @lines = []
    @live_proposal = nil
    @replaced = []
    ActiveRecord::Base.transaction(requires_new: true) do
      user.lock!
      replace_previous_distribution
      @lines = allocations
      @lines.each { |allocation| record_failure(allocation) unless allocation.save }
      raise ActiveRecord::Rollback if @errors.any?
    end
    result
  end

  # The period as if its distribution had not happened: this period's `allocation` and `sweep` rows
  # are DELETED, and only then is a fresh proposal built over what is left. Returns that proposal;
  # the rows it deleted are in #replaced.
  #
  # Public because the distribution SCREEN needs the same answer as the action underneath it. Once a
  # period has been committed its categories are funded, so a proposal computed against the ledger as
  # it stands asks for nothing — the screen would read "nothing to distribute" over a button that
  # replaces the whole split. Confirming does exactly what this method does, so the screen runs it
  # inside a transaction it rolls back and the action runs it for real. One code path, so the two
  # cannot drift.
  #
  # THIS DESTROYS ROWS. A caller that only wants to look must wrap it in
  # `ActiveRecord::Base.transaction(requires_new: true)` and `raise ActiveRecord::Rollback` — and
  # `requires_new` is not optional there either: a plain nested `transaction` opens no savepoint, so
  # the Rollback is swallowed and the deletion COMMITS. That is a screen silently destroying the
  # user's last split, which is the loudest failure in this plan.
  #
  # Not guarded by a `transaction_open?` check, deliberately: under `use_transactional_fixtures`
  # every example already runs inside one, so the guard would be green in the tests and untested
  # where it matters. The rule is stated here and both callers are one file away.
  def replace_previous_distribution
    @replaced = previous_distribution.destroy_all
    live_proposal
  end

  # What #replace_previous_distribution deleted — the last split for this period, in memory after its
  # rows are gone. Empty when the period had never been distributed, which is how the screen knows
  # whether to say it is REPLACING a split rather than writing the first one.
  def replaced = @replaced ||= []

  private

  def user = proposal.user

  # The proposal this class actually commits: built AFTER the previous distribution has been deleted,
  # and read in full before the first save.
  #
  # MEASURED, because the plan said to commit the proposal it was handed. Doing that undoes the
  # distribution on any re-run. Confirming a period a second time deletes the first split's rows, but
  # the proposal describing the replacement was computed while those rows were still there — so the
  # categories report themselves funded and ask for nothing, and the commit deletes three rows and
  # writes none. Measured on the spec's re-run fixture: Groceries $400 / Water $350 / available $250
  # fell back to $85 / $50 / $865 and the period's row count went to zero, with the button labelled
  # "distribute". The mistyped-override case, which is the reason replacement was chosen over
  # refusal, was wrong in the other direction: overriding Groceries to $40 and re-running left it at
  # $445 rather than $400, because the second proposal asked for the $360 gap while the deletion had
  # already handed the $40 back.
  #
  # A deletion is a write, so a calculator built before it is stale and a fresh one must be built
  # after it. Re-derived UNCONDITIONALLY rather than only when something was deleted — with nothing
  # deleted the two computations have the same inputs and no write between them, so they are provably
  # the same answer, and one path through the money is worth more than the queries a second path
  # would save.
  #
  # The caller's overrides survive the re-derivation because they are carried on the PROPOSAL and
  # keyed by category, not by row position. An override naming a category that no longer has a row is
  # ignored: an override edits a line, and a category with no line has no line to edit.
  def live_proposal
    @live_proposal ||= AllocationCalculator.new(
      user: user, today: proposal.today, overrides: proposal.overrides
    )
  end

  # Built, not saved. Every figure is read out of the proposal here, before the first save, because
  # the calculators underneath memoise and go stale the moment an allocation is written.
  def allocations = sweep_rows + allocation_rows

  # Sweeps are allocations too, so the ledger explains the money's whole journey rather than showing
  # a category mysteriously topped up by less than its rule.
  #
  # The amount comes from `sweeps`, which is keyed by the Category record precisely so the sweep needs
  # no second lookup. Asking a calculator again inside this loop is what
  # HoldingProjection::NetOfSweepError exists to refuse: the category's own post-sweep view would
  # re-derive a second, smaller sweep.
  def sweep_rows
    live_proposal.sweeps.map do |category, amount|
      build(from: category, to: nil, amount: amount, kind: :sweep)
    end
  end

  # A $0 allocation is not an event, and `Allocation` would refuse it anyway. This is NOT an
  # override-only case: #fill rejects rows whose ASK is zero but keeps a row whose FUNDING is zero —
  # the category below the point the money ran out, which is the ordinary shape of a short period.
  # Left unskipped, that line fails `amount > 0` and rolls the whole distribution back, so one
  # category getting nothing would leave every category unfunded.
  #
  # Only an exact zero is skipped: a NEGATIVE amount is bad input the user has to see, and it fails
  # the amount validation loudly rather than vanishing from a split it was meant to change. That
  # shape reaches here from an override AllocationCalculator#row_for deliberately did not floor, and
  # its comment says why the refusal belongs at the write rather than at the read.
  def allocation_rows
    live_proposal.rows.filter_map do |row|
      next if row.funded.zero?

      build(from: nil, to: row.category, amount: row.funded, kind: :allocation)
    end
  end

  # `from: nil` / `to: nil` IS AVAILABLE, not a missing value (§2): the root every allocation
  # ultimately draws on. A sweep runs category → NULL and an allocation runs NULL → category, which
  # is the same pair of directions the pool era wrote against the account.
  def build(from:, to:, amount:, kind:)
    Allocation.new(
      from_category: from,
      to_category: to,
      amount: amount,
      date: proposal.today,
      kind: kind,
      source_entry: source_entry
    )
  end

  # WHAT THIS SPLIT IS DISTRIBUTING, recorded on every row it writes: the income entry that arrived
  # in this period. It is PROVENANCE, not the replacement key — #previous_distribution finds the
  # split to replace by kind, period and owner, exactly as the pool era did, so a period with no
  # income at all still replaces its own split correctly and every row here simply carries `nil`.
  #
  # THE LATEST ONE WHEN THERE ARE SEVERAL, and the choice is arbitrary in the only way that is safe:
  # nothing reads this column to decide anything, so a period holding two paychecks has two equally
  # true answers and the newest is the one a person would name. `order(:date, :id)` rather than
  # `:date` alone, because two entries stamped the same instant would otherwise swap between calls.
  #
  # Memoised with `defined?`, because `nil` is the ordinary answer and `||=` would re-run the query
  # for every row of a split on a period with no income.
  def source_entry
    return @source_entry if defined?(@source_entry)

    @source_entry = Entry.incomes.where(categories: { user_id: user.id }, date: period).order(:date, :id).last
  end

  # Everything this user's last distribution wrote inside this period, and nothing else. Two filters,
  # each doing work the other cannot: `distributed` spares the user's own reallocations, and the
  # period spares earlier distributions. THE THIRD FILTER IS GONE WITH THE CONCEPT — the pool era
  # also had to spare "a second account distributing on the same day", and there is no second root.
  #
  # BOTH SIDES ARE TESTED FOR THE OWNER because either may be NULL: an allocation names only a
  # destination and a sweep names only a source, so a single-column match would take half of every
  # split. The `IN` list is a subquery over the user's own categories rather than a plucked array, so
  # a category created between the render and the confirm is not invisible to the replacement.
  #
  # `order(:id)` is not cosmetic. Every destroy here `touch`es its category (and through it the
  # user), and the distribution SCREEN holds this deletion open inside a transaction for the whole of
  # its snapshot — so two renders of the same period taking the same rows in different orders
  # deadlock, and a `create` can block behind a page view. Unordered, the order is heap order, which
  # a plain UPDATE changes. One fixed order for every caller costs nothing and makes the lock sequence
  # deterministic.
  def previous_distribution
    in_period = Allocation.distributed.where(date: period)
    mine = user.categories.select(:id)

    in_period.where(from_category_id: mine).or(in_period.where(to_category_id: mine)).order(:id)
  end

  # A period is a RANGE, and `date` is a datetime column: bounded by dates alone the last day would
  # end at its own midnight and a distribution written later that day would survive its own
  # replacement. The widening lives on User so the distribution screen's income query — `entries.date`
  # is a datetime too — cannot disagree with this one about where the period ends.
  def period = proposal.user.period_datetimes_containing(proposal.today)

  # Named by the category, which is the line the user recognises. "The side that is not the root"
  # reads both directions without branching on kind: a sweep carries only `from_category` and an
  # allocation only `to_category`, and this class writes no other shape.
  def record_failure(allocation)
    category = allocation.to_category || allocation.from_category
    @errors.concat(allocation.errors.full_messages.map { |message| "#{category.name}: #{message}" })
  end

  # A rolled-back commit reports no allocations, because the rows those records describe are gone:
  # handing them back would let a caller read amounts off a ledger that never happened.
  def result
    @errors.any? ? Result.new(allocations: [], errors: @errors) : Result.new(allocations: @lines, errors: [])
  end
end
