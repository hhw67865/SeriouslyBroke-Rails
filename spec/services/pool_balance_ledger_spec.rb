# frozen_string_literal: true

require "rails_helper"

# The five terms of a balance, grouped, for a whole set of pools.
#
# EVERY FIGURE BELOW IS A PLANTED LITERAL, and that is deliberate rather than verbose. The one
# thing this class must never do is agree with itself: an assertion of the form
# `ledger.terms_for(pool) == <something derived from the ledger>` is `x == x` and would pass
# against a class that summed the wrong column. So each term is asserted against the amount the
# fixture put there, AND against an unbatched PoolCalculator over the same pool — the reader this
# class exists to replace, built with no `terms:` at all.
RSpec.describe PoolBalanceLedger, type: :model do
  let(:user) { create(:user, :biweekly) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # Thu 20 Aug 2026, the last day of a biweekly period anchored Fri 6 Feb 2026 — the same clock
  # PoolCalculator's own sweep examples use, so a closed period here means what it means there.
  let(:today) { Date.new(2026, 8, 20) }
  let(:funded_on) { Date.new(2026, 7, 12) }
  let(:category_numbers) { (1..).each }

  # Every SQL statement one block issued, so a claim about what was and was not queried is read
  # off the database rather than off the source. Schema and transaction statements are not work
  # this class controls.
  def sql_for(&block)
    statements = []
    recorder = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record", &block)
    statements
  end

  # Plain methods rather than `let`s: the fixture already sits at rubocop's memoized-helper limit,
  # and these are two fixed dates rather than anything worth memoising. `bound` is the `as_of` the
  # bounded example uses; `after_bound` is the far side of it, where at least one row of every
  # term sits.
  def bound = Date.new(2026, 8, 1)

  def after_bound = Date.new(2026, 8, 15)

  def envelope(name) = create(:pool, :budget_pool, user: user, account: checking, name: name)

  # An entry reaching a pool the way its CATEGORY says. `on_pool:` overrides that with the entry's
  # own pool_id, which is the other arm of the entries-for-pool predicate. Each entry gets a
  # category of its own, counted rather than generated because Category validates name uniqueness
  # per user and two Faker names can collide.
  def entry(kind, amount, on:, category_pool: nil, on_pool: nil)
    category = create(:category, kind, user: user, name: "Category #{category_numbers.next}", pool: category_pool)
    create(:entry, item: create(:item, category: category), amount: amount, date: on, pool: on_pool)
  end

  def move(from:, to:, amount:, on:)
    create(:pool_movement, from_pool: from, to_pool: to, amount: amount, date: on)
  end

  describe "#terms_for" do
    # ALL FIVE TERMS ACROSS THE SET, at amounts no two of which can be swapped without an
    # assertion failing — both arms of the entries-for-pool predicate on each side, and EVERY
    # TERM WITH A ROW ON EACH SIDE OF THE `as_of` BOUND (Aug 1). That last part is what makes the
    # bounded example below able to catch a ledger that bounded four terms and forgot one; an
    # earlier fixture put only one row past the bound, so the comment claimed a guard the dates
    # did not provide.
    #
    # No pool carries all five, and that is the ledger's own domain rather than a thinner fixture:
    # Entry validates that an INCOME entry's pool must be an account, so income reaches an envelope
    # nowhere in this app and Groceries' income term is legitimately absent from the grouped hash.
    #
    #   Checking   income $190 (Jul 12) + $60 (Aug 15) — its category names Checking and the
    #                          entry names nobody
    #              expense $25 (Jul 12) — its category names GROCERIES and the entry names
    #                          Checking, so the entry's own pool_id wins, which is the half a
    #                          COALESCE written the wrong way round loses
    #              in $200 (Jul 12) + $100 (Aug 15) · out $500 (Jul 12) + $300 (Aug 15)
    #              → balance 250 − 25 + 300 − 800 = −$275, and −$135 as of Aug 1
    #
    #   Groceries  savings $30 (Jul 12) + $70 (Aug 15), reaching it by its CATEGORY
    #              expense $45 (Aug 15), over a category with no pool at all, by the ENTRY
    #              in $500 (Jul 12) + $300 (Aug 15) · out $200 (Jul 12) + $100 (Aug 15)
    #              → balance 100 − 45 + 800 − 300 = $555, and $330 as of Aug 1
    #
    #   Fresh      nothing, in any term.
    let!(:groceries) { envelope("Groceries") }
    let(:ledger) { described_class.new([checking, groceries, fresh]) }
    let!(:fresh) { envelope("Fresh Envelope") }

    # Somebody else's account, envelope and $1,887 of money, in the same two tables.
    def stranger_envelope
      stranger = create(:user, :biweekly)
      account = create(:pool, :account, user: stranger, name: "Their Checking")
      theirs = create(:pool, :budget_pool, user: stranger, account: account, name: "Their Groceries")
      category = create(:category, :savings, user: stranger, name: "Their Set Aside", pool: theirs)
      create(:entry, item: create(:item, category: category), amount: 999, date: funded_on)
      create(:pool_movement, from_pool: account, to_pool: theirs, amount: 888, date: funded_on)
      theirs
    end

    before do
      entry(:income, 190, category_pool: checking, on: funded_on)
      entry(:income, 60, category_pool: checking, on: after_bound)
      entry(:expense, 25, category_pool: groceries, on: funded_on, on_pool: checking)
      entry(:savings, 30, category_pool: groceries, on: funded_on)
      entry(:savings, 70, category_pool: groceries, on: after_bound)
      entry(:expense, 45, on: after_bound, on_pool: groceries)
      move(from: checking, to: groceries, amount: 500, on: funded_on)
      move(from: checking, to: groceries, amount: 300, on: after_bound)
      move(from: groceries, to: checking, amount: 200, on: funded_on)
      move(from: groceries, to: checking, amount: 100, on: after_bound)
    end

    it "reports each term at the amount the fixture put there", :aggregate_failures do
      expect(ledger.terms_for(checking)).to eq(
        income: 250, savings: 0, expense: 25, movements_in: 300, movements_out: 800
      )
      expect(ledger.terms_for(groceries)).to eq(
        income: 0, savings: 100, expense: 45, movements_in: 800, movements_out: 300
      )
    end

    # The same numbers read the way the app read them before this class existed. Against
    # unbatched calculators — no `terms:` anywhere on the right-hand side — so this is the
    # grouped reader answering to the per-pool one rather than to itself.
    it "agrees with an unbatched calculator, pool by pool", :aggregate_failures do
      [checking, groceries, fresh].each do |pool|
        plain = pool.calculator(today: today)
        batched = pool.calculator(today: today, terms: ledger.terms_for(pool))

        expect(batched.balance).to eq(plain.balance)
        expect(batched.contributions).to eq(plain.contributions)
        expect(batched.withdrawals).to eq(plain.withdrawals)
      end
      expect(checking.calculator(today: today).balance).to eq(-275)
      expect(groceries.calculator(today: today).balance).to eq(555)
    end

    # THE EMPTY POOL, which is the shape a grouped sum answers for by SAYING NOTHING: it has no
    # key in any of the five hashes. Asserted by TYPE as well as by value, because `0` and
    # `0.to_d` are `==` and only one of them keeps every reader downstream in BigDecimal — six
    # Integer leaks on this branch so far, every one of them at an empty set.
    it "gives a pool with no rows a decimal zero in every term", :aggregate_failures do
      terms = ledger.terms_for(fresh)

      expect(terms.values).to all(eq(0))
      expect(terms.values).to all(be_a(BigDecimal))
      expect(fresh.calculator(today: today, terms: terms).balance).to eq(0)
      expect(fresh.calculator(today: today, terms: terms).balance).to be_a(BigDecimal)
    end

    # THE TYPE GUARANTEE ON THE TWO READERS THAT BUILD ON THE TERMS RATHER THAN ON #balance.
    # `contributions` and `withdrawals` add two terms without going through #balance's coercion,
    # so on an empty pool they were `Integer + Integer` unbatched and `BigDecimal + BigDecimal`
    # batched — the same figure in two shapes depending on WHICH CALLER built the calculator,
    # which is precisely what "inert by default" is supposed to forbid. Both paths asserted,
    # because pinning either one alone passes against exactly the version that had the defect.
    it "keeps contributions and withdrawals decimal on an empty pool down both paths", :aggregate_failures do
      plain = fresh.calculator(today: today)
      batched = fresh.calculator(today: today, terms: ledger.terms_for(fresh))

      expect([plain.contributions, plain.withdrawals]).to all(be_a(BigDecimal))
      expect([batched.contributions, batched.withdrawals]).to all(be_a(BigDecimal))
      expect([plain.contributions, plain.withdrawals, batched.contributions, batched.withdrawals]).to all(eq(0))
    end

    # `as_of` belongs to the LEDGER, and it bounds ALL FIVE terms exactly as PoolCalculator#scoped
    # does. Every one of the five has a row on the far side of Aug 1 somewhere in this pair —
    # Checking's $60 of income, Groceries' $70 of savings and $45 expense, and the $300/$100
    # movements that are an `in` for one pool and an `out` for the other — so dropping `scoped`
    # from ANY term moves a figure here. MUTATION-TESTED, one term at a time: removing the
    # `scoped(...)` wrapper from `entry_totals` fails it on income/savings/expense, and from
    # `movement_totals` on both movement terms. Asserted against unbatched calculators carrying
    # the same bound as well as against literals, so neither side is the other restated.
    it "bounds every term by as_of", :aggregate_failures do
      bounded = described_class.new([checking, groceries], as_of: bound)

      expect(bounded.terms_for(checking)).to eq(
        income: 190, savings: 0, expense: 25, movements_in: 200, movements_out: 500
      )
      expect(bounded.terms_for(groceries)).to eq(
        income: 0, savings: 30, expense: 0, movements_in: 500, movements_out: 200
      )
      expect(checking.calculator(as_of: bound, today: today).balance).to eq(-135)
      expect(groceries.calculator(as_of: bound, today: today).balance).to eq(330)
      expect(groceries.calculator(as_of: bound, today: today, terms: bounded.terms_for(groceries)).balance).to eq(330)
    end

    # ANOTHER USER'S POOL IS NOT IN THE SET AND ITS MONEY IS NOT IN THE ANSWER. Both halves are
    # asserted: the stranger's rows genuinely exist (their own calculator finds them), and none of
    # them reach ours. A ledger that dropped its IN clause would pass the first half alone.
    it "excludes a pool this ledger was not built over", :aggregate_failures do
      their_envelope = stranger_envelope

      expect(their_envelope.calculator(today: today).balance).to eq(1_887)
      expect(ledger.terms_for(their_envelope)).to be_nil
      expect(ledger.terms_for(groceries)).to eq(
        income: 0, savings: 100, expense: 45, movements_in: 800, movements_out: 300
      )
    end

    # THE POINT OF THE CLASS, measured rather than asserted about. Five queries for three pools,
    # against fifteen for the same three read one at a time — and the gap widens with every pool,
    # which is what "multiples, not percents" means on a screen rendering eighteen of them.
    it "costs five queries for the whole set where per-pool calculators cost five each", :aggregate_failures do
      pools = [checking, groceries, fresh]

      grouped = sql_for { pools.each { |pool| ledger.terms_for(pool) } }
      per_pool = sql_for { pools.each { |pool| pool.calculator(today: today).balance } }

      expect(grouped.size).to eq(5)
      expect(per_pool.size).to eq(15)
    end
  end

  # WHEN THE FIVE QUERIES ACTUALLY RUN — first read, not construction.
  #
  # This is the property AllocationCommitter's re-run examples do NOT pin, and the review was
  # right about that: the committer builds its `#live_proposal` after the deletion, so those
  # examples stay green against an eager ledger too. The shape that needs a guard is the other
  # one — an object built BEFORE a write and read AFTER it, which is what a screen holding a
  # proposal across a movement actually is. Built eagerly, both expectations below report the
  # world as it was at `new`: the ledger says nothing left Checking and the proposal offers the
  # full $1,000 it no longer has.
  describe "when the five queries run" do
    let!(:groceries) { envelope("Groceries") }

    before { entry(:income, 1_000, category_pool: checking, on: funded_on) }

    it "reads the ledger at first use rather than at construction", :aggregate_failures do
      ledger = described_class.new([checking, groceries])
      proposal = AllocationCalculator.new(user: user, account: checking, today: today)

      move(from: checking, to: groceries, amount: 400, on: today)

      expect(ledger.terms_for(checking)[:movements_out]).to eq(400)
      expect(proposal.available).to eq(600)
    end
  end

  # `terms:` on PoolCalculator itself, pinned in BOTH directions. A keyword asserted only as inert
  # would pass against one that is ignored when set; a keyword asserted only as consumed would pass
  # against one that changes every caller's figures. Both, or neither is worth anything.
  describe "PoolCalculator terms:" do
    let!(:groceries) { envelope("Groceries") }
    let(:ledger) { described_class.new([checking, groceries]) }

    before do
      entry(:savings, 120, category_pool: groceries, on: funded_on)
      move(from: checking, to: groceries, amount: 500, on: funded_on)
      move(from: groceries, to: checking, amount: 200, on: funded_on)
    end

    # THE DEFAULT IS INERT, as an equality with today's numbers rather than as "something
    # sensible": every existing caller in the app builds a calculator without this keyword, and it
    # must be incapable of moving any of their figures. `terms: nil` is spelled out beside the
    # bare call because nil is what a ledger hands back for a pool it does not know, and that path
    # has to be the untouched one too.
    it "changes nothing unless it is given", :aggregate_failures do
      expect(groceries.calculator(today: today).balance).to eq(420)
      expect(groceries.calculator(today: today, terms: nil).balance).to eq(420)
      expect(groceries.calculator(today: today, terms: ledger.terms_for(groceries)).balance).to eq(420)
    end

    # AND THE INJECTED FIGURES ARE ACTUALLY CONSUMED. One term is wrong on purpose — $1,000 of
    # savings against the fixture's $120 — and the balance moves by exactly that difference. This
    # is the assertion that fails if `terms:` is accepted and then quietly ignored, which is the
    # only way this whole task could ship as a no-op.
    it "returns the injected figures rather than querying" do
      wrong = ledger.terms_for(groceries).merge(savings: 1_000.to_d)

      expect(groceries.calculator(today: today, terms: wrong).balance).to eq(1_300) # 420 + 1000 − 120
    end

    # A KeyError rather than a zero for a hash that is missing a term. The failure mode this
    # guards is silent: a `0.to_d` default there would report an envelope holding less than it
    # does, on the one path that exists to make money screens cheaper.
    it "refuses a terms hash that does not carry every term" do
      expect { groceries.calculator(today: today, terms: { income: 1.to_d }).balance }
        .to raise_error(KeyError)
    end
  end

  # THE net_of_sweep TWIN, which is where most of the batching is won and where it is easiest to
  # lose without a figure moving. PoolCalculator#sweep_adjustment builds a PLAIN calculator over
  # the same pool inside its own balance; if that twin does not receive the same terms it runs its
  # own five aggregates and the flagged calculators — the ask on Home, the ask in the fill, both
  # asks behind a reallocation's damage — go on costing exactly what they cost before.
  describe "the net_of_sweep twin" do
    let!(:groceries) { envelope("Groceries") }
    let(:ledger) { described_class.new([checking, groceries]) }

    # A rate envelope holding $85 from a period that ended over a month ago: closed, so the twin
    # is actually asked for a sweep and actually computes a balance to derive it from. Without a
    # closed period #sweepable_amount returns early and the twin never reads a term at all.
    before do
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      move(from: checking, to: groceries, amount: 85, on: funded_on)
    end

    it "reaches the same figures as an unbatched flagged calculator", :aggregate_failures do
      plain = groceries.calculator(today: today, net_of_sweep: true)
      batched = groceries.calculator(today: today, net_of_sweep: true, terms: ledger.terms_for(groceries))

      expect(plain.balance).to eq(0)
      expect(plain.required).to eq(400)
      expect(batched.balance).to eq(0)
      expect(batched.required).to eq(400)
    end

    # TEN SUMS REMOVED, NOT FIVE — the five this calculator would have run and the five its twin
    # would have run inside it. Read off the statements the balance actually issued, because the
    # figures above are identical either way and nothing else can tell the two apart.
    it "runs no balance aggregate of its own or its twin's", :aggregate_failures do
      plain = groceries.calculator(today: today, net_of_sweep: true)
      batched = groceries.calculator(today: today, net_of_sweep: true, terms: ledger.terms_for(groceries))

      unbatched_sums = sql_for { plain.balance }.grep(/SUM/)
      batched_sums = sql_for { batched.balance }.grep(/SUM/)

      expect(unbatched_sums.size).to eq(10)
      expect(batched_sums).to be_empty
    end
  end
end
