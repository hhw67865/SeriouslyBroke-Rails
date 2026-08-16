# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomePresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def envelope(name, priority:) = envelope_in(checking, name, priority: priority)

  def envelope_in(account, name, priority:)
    create(:pool, :budget_pool, user: user, account: account, name: name, priority: priority)
  end

  def savings_goal(name, priority:, target: 1_200)
    create(:pool, :savings_pool, user: user, account: checking, name: name, target_amount: target, priority: priority)
  end

  # A flat per-period rule: the catch-all envelope shape, and the one that makes
  # `required` exactly the amount asked for.
  def rate(pool, amount) = create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)

  def bill(pool, amount:, due:) = create(:pool_budget, :one_time, pool: pool, amount: amount, anchor_date: due)

  # A rule that rolls: its due date moves with the cycles that have gone by, which is what
  # makes it depend on which day the calculator is asked about.
  def rolling(pool, amount:, anchor:)
    create(:pool_budget, pool: pool, amount: amount, interval_months: 1, anchor_date: anchor)
  end

  # Category names are unique per user, so both of these name themselves after the
  # account — an example may fund two accounts.
  def deposit(account, amount)
    category = create(:category, :income, user: user, pool: account, name: "#{account.name} pay")
    create(:entry, item: create(:item, category: category), amount: amount, date: today)
  end

  def overdraw(account, amount)
    category = create(:category, :expense, user: user, pool: account, name: "#{account.name} fees")
    create(:entry, item: create(:item, category: category), amount: amount, date: today)
  end

  describe "#accounts" do
    it "returns only this user's accounts, by name", :aggregate_failures do
      # `checking` is forced FIRST so insertion order is Checking, Ally — the reverse of
      # the expected answer. With Ally created first the rows come back alphabetically
      # already, and dropping `.order(:name)` would still pass. Account order drives the
      # Home screen's section order, so it has to be pinned rather than inherited from
      # whatever Postgres hands back.
      checking
      ally = create(:pool, :account, user: user, name: "Ally")
      envelope("Groceries", priority: 1)
      create(:pool, :account, user: create(:user), name: "Someone Else")

      expect(presenter.accounts).to eq([ally, checking])
      expect(presenter.accounts.map(&:name)).to eq(["Ally", "Checking"])
    end
  end

  describe "#orphan_pools" do
    it "returns account-less pools, by priority then name, and nothing else", :aggregate_failures do
      envelope("Has An Account", priority: 1)
      # Reverse alphabetical at a shared priority, so the name tie-break is visible.
      zoo = create(:pool, user: user, name: "Zoo Fund", target_amount: 500, priority: 2)
      apples = create(:pool, user: user, name: "Apples Fund", target_amount: 500, priority: 2)
      urgent = create(:pool, user: user, name: "Urgent Fund", target_amount: 500, priority: 1)

      expect(presenter.orphan_pools).to eq([urgent, apples, zoo])
      # The complement of #pools_for: between them they must cover every pool, or a
      # view that renders both still leaves something invisible.
      expect(presenter.orphan_pools & presenter.pools_for(checking)).to be_empty
    end
  end

  describe "#orphan_pools_owed" do
    # The set #orphan_required is summed from, which is NOT every orphan: the standing band
    # prints the figure and this count in one sentence, and a reader who divides them has to
    # get an answer about the same pools the figure came from.
    it "returns only the account-less pools asking for something", :aggregate_failures do
      owed = create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1)
      rate(owed, 200)
      # A goal with no rule on it yet asks for nothing this period, so it owns none of the figure.
      create(:pool, user: user, name: "Finished Goal", target_amount: 5_000, priority: 2)
      rate(envelope("Rent", priority: 3), 400)

      expect(presenter.orphan_pools_owed).to eq([owed])
      expect(presenter.orphan_pools.size).to eq(2)
      expect(presenter.orphan_required).to eq(200)
    end

    it "is empty when no account-less pool asks for anything", :aggregate_failures do
      create(:pool, user: user, name: "Finished Goal", target_amount: 5_000, priority: 1)

      expect(presenter.orphan_pools_owed).to be_empty
      expect(presenter.orphan_required).to eq(0)
    end
  end

  describe "#pools_for" do
    it "returns the account's own pools by priority then name, and no others", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      # Reverse alphabetical at a shared priority, so the name tie-break is visible.
      zoo = envelope("Zoo", priority: 1)
      apples = envelope("Apples", priority: 1)
      later = envelope("Later", priority: 2)
      elsewhere = envelope_in(ally, "Elsewhere", priority: 0)

      expect(presenter.pools_for(checking)).to eq([apples, zoo, later])
      expect(presenter.pools_for(ally)).to eq([elsewhere])
    end
  end

  describe "#status_for" do
    let(:dentist) do
      envelope("Dentist", priority: 1).tap { |pool| bill(pool, amount: 300, due: Date.new(2026, 2, 14)) }
    end

    # The whole reason this method exists. Asserted in BOTH directions: the second
    # expectation proves a bare `pool.status` genuinely disagrees on this data, so
    # the first is pinning the injected day rather than passing by coincidence.
    it "computes against the injected day, not Date.current", :aggregate_failures do
      travel_to(Date.new(2026, 2, 20)) do
        expect(presenter.status_for(dentist).state).to eq(:wont_make_it)
        expect(dentist.status.state).not_to eq(:wont_make_it)
      end
    end

    it "memoises per pool so a row does not rebuild its status" do
      first_call = presenter.status_for(dentist)

      expect(presenter.status_for(dentist)).to be(first_call)
    end

    it "keeps distinct pools on distinct statuses", :aggregate_failures do
      quiet = envelope("Groceries", priority: 2)
      rate(quiet, 100)

      expect(presenter.status_for(dentist)).not_to be(presenter.status_for(quiet))
      expect(presenter.status_for(quiet).state).not_to eq(:wont_make_it)
    end
  end

  describe "#dated_rules_for" do
    # An expanded row prints one line per dated rule, earliest first. An anchorless rule has
    # no date to print, so it is not one of these lines — and a row whose rules are ALL
    # anchorless renders its own sentence instead of an empty box.
    it "returns the anchored rules earliest due first, and nothing else", :aggregate_failures do
      utilities = envelope("Utilities", priority: 1)
      electric = bill(utilities, amount: 90, due: Date.new(2026, 3, 1))
      water = bill(utilities, amount: 40, due: Date.new(2026, 2, 20))
      rate(utilities, 25)

      expect(presenter.dated_rules_for(utilities)).to eq(
        [
          [water, Date.new(2026, 2, 20)],
          [electric, Date.new(2026, 3, 1)]
        ]
      )
    end

    it "is empty for a pool funded only at a rate" do
      groceries = envelope("Groceries", priority: 1)
      rate(groceries, 400)

      expect(presenter.dated_rules_for(groceries)).to be_empty
    end

    # The same hazard as #status_for, one level down: `budget.calculator` defaults to
    # Date.current, so a partial building its own would date these rules against a different
    # day than every other figure on the screen. Asserted in BOTH directions — the second
    # expectation proves a bare `budget.calculator` genuinely disagrees on this data.
    it "dates a rolling rule against the injected day, not Date.current", :aggregate_failures do
      utilities = envelope("Utilities", priority: 1)
      rule = rolling(utilities, amount: 120, anchor: Date.new(2026, 1, 1))

      travel_to(Date.new(2026, 6, 9)) do
        expect(presenter.dated_rules_for(utilities)).to eq([[rule, Date.new(2026, 3, 1)]])
        expect(rule.calculator.due_date).to eq(Date.new(2026, 7, 1))
      end
    end

    it "memoises per pool so a row does not rebuild its rules" do
      utilities = envelope("Utilities", priority: 1)
      bill(utilities, amount: 90, due: Date.new(2026, 3, 1))
      first_call = presenter.dated_rules_for(utilities)

      expect(presenter.dated_rules_for(utilities)).to be(first_call)
    end
  end

  describe "#available" do
    it "is the account's unclaimed cash" do
      deposit(checking, 2_400)

      expect(presenter.available).to eq(2_400)
    end

    # An overdrawn account is a debt to surface, not a source to spend from. Netting it
    # would give a number true about net worth and false about what can be allocated,
    # which is the only question this screen asks.
    it "ignores an overdrawn account rather than netting it away", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      deposit(checking, 1_000)
      overdraw(ally, 400)

      # #current_buffer_for still tells the truth about the account itself — Tasks 6/7 render
      # the overdraft from here. It is only the fundable total that excludes it.
      expect(presenter.current_buffer_for(checking)).to eq(1_000)
      expect(presenter.current_buffer_for(ally)).to eq(-400)
      expect(presenter.available).to eq(1_000)
    end

    it "is a decimal zero, not an integer, for a user with nothing", :aggregate_failures do
      expect(presenter.available).to eq(0)
      expect(presenter.available).to be_a(BigDecimal)
      expect(presenter.current_buffer_for(checking)).to be_a(BigDecimal)
    end
  end

  describe "#total_required" do
    it "sums what every pool needs this period" do
      rate(envelope("Groceries", priority: 1), 400)
      rate(envelope("Gas", priority: 2), 80)

      expect(presenter.total_required).to eq(480)
    end

    it "counts savings goals alongside budget envelopes", :aggregate_failures do
      rate(envelope("Groceries", priority: 1), 400)
      rate(savings_goal("Vacation", priority: 2), 150)

      expect(presenter.total_required).to eq(550)
      expect(presenter.waterfall.map { |r| r[:pool].name }).to eq(["Groceries", "Vacation"])
    end

    it "is a decimal zero, not an integer, for a user with no pools", :aggregate_failures do
      expect(presenter.total_required).to eq(0)
      expect(presenter.total_required).to be_a(BigDecimal)
      expect(presenter.shortfall).to be_a(BigDecimal)
    end
  end

  describe "#waterfall" do
    before do
      rate(envelope("Rent", priority: 1), 500)
      rate(envelope("Groceries", priority: 2), 400)
      rate(envelope("Vacation", priority: 3), 150)
      deposit(checking, 700)
    end

    it "fills top-down by priority and marks the cutoff", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(["Rent", "Groceries", "Vacation"])
      expect(rows[0][:funded]).to eq(500)
      expect(rows[1][:funded]).to eq(200)
      expect(rows[2][:funded]).to eq(0)
    end

    it "records each row's shortfall", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows[0][:short]).to eq(0)
      expect(rows[1][:short]).to eq(200)
      expect(rows[2][:short]).to eq(150)
    end

    it "reports the total gap", :aggregate_failures do
      expect(presenter.shortfall).to eq(350)
      expect(presenter).not_to be_covered
    end

    it "records what each row asked for, funded or not", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.pluck(:needed)).to eq([500, 400, 150])
      # `needed` is the ask, never the outcome: the cut-off row must still state its
      # full requirement, or the screen cannot show what running out actually cost.
      expect(rows.map { |r| r[:needed] - r[:funded] }).to eq(rows.pluck(:short))
    end
  end

  # Separate from the block above because that one's `before` fixes three distinct
  # priorities, which is exactly the shape that cannot see a tie-break at all.
  describe "#waterfall priority ties" do
    it "breaks a tie by name so the same data funds the same pool every load", :aggregate_failures do
      # Written in reverse alphabetical order on purpose: the pools query carries no
      # ORDER BY, so the database hands these back in insertion order and a sort on
      # priority alone would fund Zoo first for no reason the user can see.
      rate(envelope("Zoo", priority: 1), 300)
      rate(envelope("Apples", priority: 1), 300)
      deposit(checking, 300)

      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(["Apples", "Zoo"])
      # Keyed by name rather than by row index: the tie is not cosmetic, it decides
      # which envelope the money actually reaches, and a positional assertion would
      # hold just as well with the two pools swapped.
      expect(rows.to_h { |r| [r[:pool].name, r[:funded]] }).to eq("Apples" => 300, "Zoo" => 0)
    end
  end

  describe "#waterfall with an overdrawn user" do
    # `pot.clamp(0.to_d, needed)` is the guard: a negative pot would otherwise raise
    # ArgumentError on `clamp(0, negative)` the way PoolCalculator's draft did, turning
    # the whole Home screen into a 500 for the users most in need of reading it. The
    # clamp in #account_pots means it never gets that far, and both hold.
    it "funds nothing and still states every ask", :aggregate_failures do
      overdraw(checking, 500)
      rate(envelope("Rent", priority: 1), 300)

      rows = presenter.waterfall

      expect(presenter.current_buffer_for(checking)).to eq(-500)
      expect(presenter.available).to eq(0)
      expect(rows.pluck(:funded)).to eq([0])
      expect(rows.pluck(:short)).to eq([300])
      expect(presenter.shortfall).to eq(300)
      expect(presenter).not_to be_covered
    end
  end

  describe "#waterfall across accounts" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    # The ruling this pins: money stays in the account it is sitting in. A global pot
    # would fund Checking's envelope out of Ally's cash — a transfer nobody can perform,
    # since the spec dropped cross-account movement.
    it "funds each envelope only from its own account", :aggregate_failures do
      deposit(ally, 1_000)
      # Checking gets nothing, so its envelope must go unfunded however rich Ally is.
      rate(envelope_in(checking, "Rent", priority: 1), 800)
      rate(envelope_in(ally, "Groceries", priority: 2), 400)

      funded = presenter.waterfall.to_h { |r| [r[:pool].name, r[:funded]] }

      expect(presenter.available).to eq(1_000)
      expect(funded).to eq("Rent" => 0, "Groceries" => 400)
      # The gap follows the rows, not `total_required - available` (1200 - 1000 = 200).
      # Rent is unfundable in full, and the headline has to say so.
      expect(presenter.shortfall).to eq(800)
      expect(presenter).not_to be_covered
    end

    # The case that was green under both readings of #shortfall and is the whole reason
    # the derived version won: nothing is wrong with the *total*, only with where it sits.
    it "is not covered when the money is in an account with no envelopes", :aggregate_failures do
      deposit(ally, 1_000)
      rate(envelope_in(checking, "Rent", priority: 1), 300)

      expect(presenter.total_required).to eq(300)
      expect(presenter.available).to eq(1_000)
      # `total_required - available` is -700, which clamps to 0 and reads "covered" —
      # above a Rent row funded at zero.
      expect(presenter.waterfall.pluck(:funded)).to eq([0])
      expect(presenter.shortfall).to eq(300)
      expect(presenter).not_to be_covered
    end

    # Priority orders the whole screen, but each account's pot drains independently:
    # a high-priority envelope in one account cannot starve a lower-priority one in
    # another, because it was never able to spend that account's money.
    it "drains each account's pot independently", :aggregate_failures do
      deposit(checking, 300)
      deposit(ally, 500)
      rate(envelope_in(checking, "Rent", priority: 1), 900)
      rate(envelope_in(ally, "Savings Top-up", priority: 2), 400)

      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(["Rent", "Savings Top-up"])
      expect(rows.to_h { |r| [r[:pool].name, [r[:funded], r[:short]]] })
        .to eq("Rent" => [300, 600], "Savings Top-up" => [400, 0])
      # 1300 required against 800 available would say 500. Only 600 is reachable.
      expect(presenter.shortfall).to eq(600)
    end

    # The reversal of Task 4's ruling. An orphan used to sit here funded at zero, which put
    # its ask into #shortfall: a setup problem — the money may be in Checking already, with
    # nowhere to go — reported as money the user does not have. It also dragged the cutoff
    # line above rows funded in full, since an orphan at priority 1 has `funded == 0`.
    it "leaves an account-less pool out of the rows entirely", :aggregate_failures do
      deposit(checking, 1_000)
      # Savings pools may stay account-less until Plan 3's backfill, so this shape is
      # reachable today — and must not help itself to whichever pot comes first.
      orphan = create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1)
      rate(orphan, 200)
      rate(envelope_in(checking, "Rent", priority: 2), 400)

      expect(presenter.waterfall.map { |r| r[:pool].name }).to eq(["Rent"])
      expect(presenter.available).to eq(1_000)
      # Still owed — the Budget page needs the honest total — but not a funding gap.
      expect(presenter.total_required).to eq(600)
      expect(presenter.shortfall).to eq(0)
      expect(presenter).to be_covered
      # Which leaves the attention list as the one place it is spoken for.
      expect(presenter.orphan_pools).to eq([orphan])
    end

    # Seen on the screen, not in a spec: a pool that asks for nothing rendered "$0.00 of
    # $0.00" — and below the red "ran out here" line that reads as "this got nothing because
    # the money ran out" when the truth is "this needed nothing". The waterfall answers where
    # the money goes, and a pool with no ask is not part of that story.
    #
    # Arithmetic-neutral by construction: a zero-need row contributes 0 to `needed`, `funded`
    # and `short`, so #shortfall, #projected_buffer and #orphan_required cannot move — which
    # the expectations below pin rather than assume.
    it "leaves out a pool that asks for nothing this period", :aggregate_failures do
      deposit(checking, 500)
      # Funded in full already, so its `required` is zero — the commonest way to reach this.
      settled = envelope("Rent", priority: 1)
      rate(settled, 300)
      create(:pool_movement, from_pool: checking, to_pool: settled, amount: 300)
      rate(envelope("Groceries", priority: 2), 400)

      expect(presenter.waterfall.map { |r| r[:pool].name }).to eq(["Groceries"])
      expect(presenter.total_required).to eq(400)
      expect(presenter.shortfall).to eq(200)
      expect(presenter.projected_buffer).to eq(0)
    end

    it "does not spend down the cash it reports as available", :aggregate_failures do
      deposit(checking, 500)
      rate(envelope_in(checking, "Rent", priority: 1), 400)

      # #account_pots is spent down as the waterfall fills, so a memoised pots hash would
      # leave #available summing the leftovers. Waterfall FIRST, then the headline.
      expect(presenter.waterfall.pluck(:funded)).to eq([400])
      expect(presenter.available).to eq(500)
      expect(presenter.waterfall.pluck(:funded)).to eq([400])
    end
  end

  describe "#covered?" do
    it "is true when available meets the requirement", :aggregate_failures do
      rate(envelope("Groceries", priority: 1), 100)
      deposit(checking, 500)

      expect(presenter).to be_covered
      expect(presenter.shortfall).to eq(0)
    end
  end

  describe "#overdrawn_accounts" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "names the accounts below zero and no others", :aggregate_failures do
      deposit(ally, 500)
      overdraw(checking, 400)

      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
      expect(presenter.status_for(presenter.overdrawn_accounts.first).state).to eq(:overdrawn)
    end

    it "is empty when every account is in the black" do
      deposit(checking, 10)

      expect(presenter.overdrawn_accounts).to be_empty
    end

    # The whole reason this reader exists. Both headline figures are right to leave the
    # overdraft out — #available because you cannot spend it, #shortfall because a $300
    # rule is $300 short, not $800 — and between them a real $500 debt would render
    # nowhere at all. #current_buffer_for has always known; nothing was asking it.
    it "reports a debt that neither headline figure contains", :aggregate_failures do
      overdraw(checking, 500)
      rate(envelope("Rent", priority: 1), 300)

      expect(presenter.available).to eq(0)
      expect(presenter.shortfall).to eq(300)
      expect(presenter.current_buffer_for(checking)).to eq(-500)
      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
    end
  end

  describe "#projected_buffer" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "is what stays put once every reachable pool is funded", :aggregate_failures do
      deposit(checking, 500)
      rate(envelope("Groceries", priority: 1), 100)

      expect(presenter).to be_covered
      expect(presenter.projected_buffer).to eq(400)
    end

    # The bug the orphan ruling would otherwise introduce: an account-less pool counts in
    # #total_required and can never be funded, so `available - total_required` prints a
    # negative buffer at a user whose accounts are in perfect order.
    it "is never negative because of a pool no account can fund", :aggregate_failures do
      deposit(checking, 100)
      rate(create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1), 500)

      expect(presenter.total_required).to eq(500)
      expect(presenter.available - presenter.total_required).to eq(-400)
      expect(presenter).to be_covered
      expect(presenter.projected_buffer).to eq(100)
    end

    it "is zero when a single account is short, where the two figures already agree", :aggregate_failures do
      deposit(checking, 150)
      rate(envelope("Groceries", priority: 1), 400)

      expect(presenter.shortfall).to eq(presenter.total_required - presenter.available)
      expect(presenter.projected_buffer).to eq(0)
    end

    it "is the cash this period's pools cannot reach", :aggregate_failures do
      deposit(ally, 1_000)
      rate(envelope_in(checking, "Rent", priority: 1), 400)

      expect(presenter.shortfall).to eq(400)
      # What a reader subtracting the standing band's two figures would get instead.
      expect(presenter.total_required - presenter.available).to eq(-600)
      expect(presenter.projected_buffer).to eq(1_000)
    end

    it "counts only the surplus of an account that funds pools of its own", :aggregate_failures do
      deposit(checking, 100)
      deposit(ally, 500)
      rate(envelope_in(checking, "Rent", priority: 1), 400)
      rate(envelope_in(ally, "Groceries", priority: 2), 200)

      # Checking funds 100 of 400; Ally funds its 200 and keeps 300 nothing can use.
      expect(presenter.shortfall).to eq(300)
      expect(presenter.projected_buffer).to eq(300)
    end
  end

  describe "#orphan_required" do
    it "is what the account-less pools ask for", :aggregate_failures do
      deposit(checking, 100)
      rate(envelope_in(checking, "Rent", priority: 2), 400)
      rate(create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1), 200)

      expect(presenter.total_required).to eq(600)
      expect(presenter.orphan_required).to eq(200)
      # Exactly what a reader subtracting the two headline figures is left holding.
      expect((presenter.total_required - presenter.available) - presenter.shortfall)
        .to eq(presenter.orphan_required - presenter.projected_buffer)
    end

    it "is zero when every pool has an account", :aggregate_failures do
      deposit(checking, 100)
      rate(envelope("Rent", priority: 1), 400)

      expect(presenter.orphan_required).to eq(0)
      expect(presenter.total_required - presenter.available).to eq(presenter.shortfall)
    end
  end

  describe "#attention_pools" do
    it "returns only pools whose status needs attention" do
      quiet = envelope("Groceries", priority: 1)
      rate(quiet, 100)
      create(:pool_movement, from_pool: checking, to_pool: quiet, amount: 100)

      bill(envelope("Dentist", priority: 2), amount: 300, due: Date.new(2026, 2, 14))

      expect(presenter.attention_pools.map(&:name)).to eq(["Dentist"])
    end

    it "lists them by priority, then name" do
      # Created in the reverse of the expected order, so insertion order alone cannot
      # produce the answer: `all_pools` has no ORDER BY and Postgres hands rows back in
      # heap order, which a plain UPDATE relocates.
      [["Zoo", 2], ["Apples", 2], ["Urgent", 1]].each do |name, priority|
        bill(envelope(name, priority: priority), amount: 300, due: Date.new(2026, 2, 14))
      end

      expect(presenter.attention_pools.map(&:name)).to eq(["Urgent", "Apples", "Zoo"])
    end
  end

  describe "#structurally_underwater?" do
    it "is true when the rules need more than typical income" do
      rate(envelope("Rent", priority: 1), 3_000)

      expect(presenter).to be_structurally_underwater
    end

    it "is false when they fit" do
      rate(envelope("Rent", priority: 1), 500)

      expect(presenter).not_to be_structurally_underwater
    end

    # The boundary the `>` sits on. Rules that consume the declared income exactly are
    # not a structural problem — there is nothing reallocation could not still fix —
    # so this must not fire, and a `>=` here would tell a user their budget is
    # impossible on the day it balances.
    it "is false when the rules land exactly on typical income", :aggregate_failures do
      rate(envelope("Rent", priority: 1), 2_400)

      expect(presenter.total_required).to eq(user.typical_income)
      expect(presenter).not_to be_structurally_underwater
    end

    it "is false when typical income is unset" do
      user.update!(typical_income: nil)
      rate(envelope("Rent", priority: 1), 3_000)

      expect(presenter).not_to be_structurally_underwater
    end
  end
end
