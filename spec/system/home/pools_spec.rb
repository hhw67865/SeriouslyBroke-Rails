# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Pools", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }

  before { sign_in user, scope: :user }

  def group(name) = find("[data-pool-group='#{name}']")

  def row(name) = find("[data-pool-name='#{name}']")

  # A rate envelope: refilled every period, and the shape that reads `left to spend`.
  def envelope(name, rate:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
    pool
  end

  # A bill that accumulates toward a date — the shape that reads `on track` while it is
  # being filled on schedule.
  def accumulating(name, amount:, due:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, pool: pool, amount: amount, interval_months: 1, anchor_date: due)
    pool
  end

  # A one-off bill with no interval to spread it over.
  def one_off(name, amount:, due:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :one_time, pool: pool, amount: amount, anchor_date: due)
    pool
  end

  def deposit(amount, into: checking)
    category = create(:category, :income, user: user, pool: into, name: "#{into.name} pay")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  def fund(pool, amount, on: Time.zone.now)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def spend(pool, amount)
    category = create(:category, :expense, user: user, pool: pool, name: "#{pool.name} spend")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # A rule the user actually pays: an item is the only fulfilment signal BudgetCalculator
  # accepts, and therefore the only way a rule can be late.
  def payable(name, amount:, due:, interval: 1, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    category = create(:category, :expense, user: user, pool: pool, name: "#{name} bills")
    item = create(:item, category: category, name: "#{name} Bill")
    create(:pool_budget, pool: pool, item: item, amount: amount, interval_months: interval, anchor_date: due)
    pool
  end

  # The two buffers are deliberately different numbers here: $1,000 in with $100 already
  # moved into the envelope leaves the account holding $900 NOW, and the $300 the rule still
  # wants this period leaves $600 AFTER the distribution. A band printing the other one is a
  # plausible wrong figure, which is the whole reason the readers are named for their moment.
  #
  # And the COPY has to carry that distinction too, which is what this pins. Both figures
  # used to be introduced by the bare word "buffer" on one screen — "$600.00 stays in your
  # buffer" above "buffer $900.00 of $2,000.00" — so the reader had no way to tell which
  # moment either described, or whether one was a breakdown of the other. Each assertion
  # below includes the time word, so dropping it fails here rather than passing on a
  # substring of the old wording.
  it "groups pools under their account and shows the buffer", :aggregate_failures do
    deposit(1_000)
    fund(envelope("Groceries", rate: 400), 100)

    visit root_path

    expect(page).to have_content("Checking")
    expect(group("Checking")).to have_content("Groceries")
    expect(group("Checking")).to have_content("$100.00 left")
    expect(group("Checking")).to have_content("buffer now $900.00")
    # "target", not "of": a bare "of $2,000.00" never said what the figure measures.
    expect(group("Checking")).to have_content("target $2,000.00")
    expect(page).to have_content("$600.00 stays in your buffer after this period")
  end

  it "shows a balance on an on-track pool" do
    deposit(2_000)
    fund(accumulating("Rent", amount: 2_000, due: Date.current + 2.months), 2_000)

    visit root_path

    expect(row("Rent")).to have_content("$2,000.00 · on track")
  end

  # Principle 2 on the row that used to break it: a savings pool with no dated rule could
  # reach no state but `left to spend`, so a vacation fund rendered "$424.00 left" — a
  # spendable number for money that is not spendable.
  it "shows a savings pool saving toward its target, never as money to spend", :aggregate_failures do
    goal = create(:pool, :savings_pool, user: user, account: checking, name: "Vacation", target_amount: 2_400)
    deposit(500)
    fund(goal, 424)

    visit root_path

    expect(row("Vacation")).to have_content("$424.00 of $2,400.00")
    expect(row("Vacation")).to have_no_content("left")
    # Accumulating on plan is not trouble, so it stays one quiet line.
    expect(row("Vacation")["data-expanded"]).to eq("false")
  end

  it "auto-expands a pool that needs attention", :aggregate_failures do
    one_off("Dentist", amount: 300, due: Date.current + 3.days)

    visit root_path

    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Dentist")).to have_content("won't make it")
    # The auto-expand exists to show the rule behind the trouble. A `data-expanded` flag
    # over an empty row would satisfy the attribute and none of the point.
    expect(row("Dentist")).to have_css("[data-role='pool-detail']")
    expect(row("Dentist")).to have_content("$300.00")
    expect(row("Dentist")).to have_content((Date.current + 3.days).strftime("%b %-d"))
  end

  # The two states that render a date the user has to act on. Both were pinned at the label
  # and state layers and neither had ever been seen through a real row, which is where the
  # date and the rule beneath it actually meet.
  it "shows an overdue pool with the date that passed and the rule behind it", :aggregate_failures do
    payable("Utilities", amount: 120, due: Date.current - 10.days)

    visit root_path

    expect(row("Utilities")).to have_content("overdue · was #{(Date.current - 10.days).strftime("%b %-d")}")
    expect(row("Utilities")["data-expanded"]).to eq("true")
    expect(row("Utilities")).to have_content("Utilities Bill")
    expect(row("Utilities")).to have_content("$120.00 · #{(Date.current - 10.days).strftime("%b %-d")}")
  end

  it "shows a behind pool with the rule it is behind on", :aggregate_failures do
    pool = create(:pool, :budget_pool, user: user, account: checking, name: "Car Insurance", priority: 1)
    create(:pool_budget, pool: pool, amount: 1_200, interval_months: 6, anchor_date: Date.current + 3.months)

    visit root_path

    # The lag is a function of how many boundaries fall inside the cycle, so the figure is
    # matched by shape rather than pinned to a date arithmetic this example does not own.
    expect(row("Car Insurance")).to have_content(/behind \$\d[\d,]*\.\d\d/)
    expect(row("Car Insurance")["data-expanded"]).to eq("true")
    expect(row("Car Insurance")).to have_content("Every 6 months")
    expect(row("Car Insurance")).to have_content("$1,200.00 · #{(Date.current + 3.months).strftime("%b %-d")}")
  end

  # `rules.empty?` does NOT imply a rate rule exists. A pool with no rules at all and a
  # negative balance reaches :overdrawn — the only state guarded on the balance alone — and
  # expands, so the fallback sentence has to be true of what is actually there. Both halves,
  # because a sentence that is right in one shape and false in the other is pinned by neither.
  it "explains an overdrawn rate envelope by its rate", :aggregate_failures do
    deposit(200)
    dining = envelope("Dining Out", rate: 150)
    fund(dining, 100)
    spend(dining, 180)

    visit root_path

    expect(row("Dining Out")).to have_content("overdrawn $80.00")
    expect(row("Dining Out")).to have_content("refills at its rate")
    expect(row("Dining Out")).to have_no_content("nothing funds it")
  end

  it "says so plainly when an overdrawn pool has no rules at all", :aggregate_failures do
    mystery = create(:pool, :budget_pool, user: user, account: checking, name: "Mystery", priority: 1)
    spend(mystery, 80)

    visit root_path

    expect(row("Mystery")).to have_content("overdrawn $80.00")
    expect(row("Mystery")).to have_content("nothing funds it")
    # The refill promise would be a flat untruth here: nothing refills this pool.
    expect(row("Mystery")).to have_no_content("refills at its rate")
  end

  # Plan 2b decision 1, on the row it changes. The spec's original §7.2 had an expired rate
  # envelope render `$0` with its leftover already shown in the buffer; that would put the
  # screen at odds with the ledger, because the $60 is still physically in Groceries until a
  # distribution moves it, and `Σ pools == your bank balance` is the invariant the app rests
  # on. So the real balance renders, marked as belonging to a period that is over.
  #
  # Both envelopes on ONE screen, at the identical balance and the identical rule, differing
  # only in which side of a period boundary their money arrived on. Split into two examples
  # the negative half would pass against a view that never says "last period" at all.
  it "marks a rate envelope whose period has ended, and only that one", :aggregate_failures do
    deposit(1_000)
    fund(envelope("Groceries", rate: 400, priority: 1), 60, on: Date.current - 20.days)
    fund(envelope("Dining Out", rate: 400, priority: 2), 60, on: Date.current)

    visit root_path

    expect(row("Groceries")).to have_content("$60.00 left · last period")
    expect(row("Dining Out")).to have_content("$60.00 left")
    expect(row("Dining Out")).to have_no_content("last period")
  end

  it "leaves a quiet pool collapsed", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(row("Groceries")["data-expanded"]).to eq("false")
    # The other half of the same rule: a quiet pool renders its one line and nothing else.
    expect(row("Groceries")).to have_no_css("[data-role='pool-detail']")
  end

  # Two pools, one of each kind, on the same screen: the auto-expanded rows have to be
  # EXACTLY the ones needing attention. Either half alone passes against a view that
  # expands everything, or nothing.
  it "expands only the rows that need attention", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)
    one_off("Dentist", amount: 300, due: Date.current + 3.days, priority: 2)

    visit root_path

    expect(page).to have_css("[data-expanded='true']", count: 1)
    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Groceries")["data-expanded"]).to eq("false")
  end

  # A pool with no account is excluded from #pools_for, so a band built purely as
  # "for each account, render its pools" renders it nowhere at all — and an account-less
  # savings pool is the ordinary shape until Plan 3's backfill.
  it "gives a pool with no account a group of its own", :aggregate_failures do
    create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(group("No account")).to have_content("Old Goal")
    expect(group("No account")).to have_content("nothing can fund")
    # And it must not be filed under an account it does not belong to.
    expect(group("Checking")).to have_no_content("Old Goal")
    expect(group("No account")).to have_no_content("Groceries")
    # Its own status is quiet — a goal at $0 of $5,000 with no dated rule reads `saving` —
    # so only the "nothing can fund it" half makes this a problem, and
    # the row still has to open with the rest of the trouble rather than sit collapsed
    # under a red heading.
    expect(row("Old Goal")["data-expanded"]).to eq("true")
    expect(row("Old Goal")).to have_content("no distribution can reach it")
  end

  # ** THE DUE DATE ON A QUIET ORPHAN — the row the 2d task 6 refactor silently changed, and the
  #    one shape the byte-for-byte diff of Home could not see. **
  #
  # `_pool_row`'s date clause gates on the STATUS being quiet. Moved onto the row object it briefly
  # gated on the ROW being quiet, and a row is not quiet when it is an orphan — so an orphan whose
  # own status is `on track` and which has an anchored rule went from
  # `$300.00 · on track · Oct 17` to `$300.00 · on track`, losing the only date on the line.
  # `pool_status_label` knows nothing about orphanhood, so the "the label already said the date"
  # argument that makes the gate safe for attention rows is false here.
  #
  # THE BLIND SPOT IS WORTH NAMING: the refactor was verified by diffing Home's whole rendered HTML
  # against the demo database, byte for byte, and that diff was clean — because no pool on the demo
  # is BOTH orphaned and quiet-with-a-dated-rule. A rendering diff can only see the states its data
  # reaches; this pair is the assertion that does not depend on which pools happen to exist.
  #
  # Scoped to `span.text-sm`, which is the status line: an orphan row is auto-expanded, and the
  # detail underneath it prints every dated rule's own date — so `have_no_content(date)` against the
  # whole row would fail on text that is supposed to be there.
  describe "an orphan pool's due date", :aggregate_failures do
    def status_line(name) = find("[data-pool-name='#{name}'] span.text-sm")

    # A SAVINGS pool, because it is the only kind that can be an orphan at all — `Pool` refuses a
    # budget pool with no account ("Account must be set for budget pools"), which is why
    # HomePresenter#orphan_pools calls an account-less savings goal the ordinary shape. The anchored
    # rule is what takes it OUT of the `saving` state (`PoolStatus#saving?` requires no anchored
    # rule) and into the quiet `on track` one, which is the only quiet state carrying a date.
    def orphan_with_rule(name, amount:, due:)
      pool = create(:pool, user: user, name: name, target_amount: 5_000, priority: 1)
      create(:pool_budget, pool: pool, amount: amount, interval_months: 1, anchor_date: due)
      pool
    end

    it "prints it when the pool's own status is quiet" do
      due = Date.current + 2.months
      pool = orphan_with_rule("Old Goal", amount: 300, due: due)
      create(:pool_movement, from_pool: checking, to_pool: pool, amount: 300, date: Date.current)

      visit root_path

      expect(status_line("Old Goal")).to have_content("on track")
      expect(status_line("Old Goal")).to have_content(due.strftime("%b %-d"))
    end

    # The other direction, on an orphan whose OWN status needs attention. Overdrawn is the state to
    # reach it with: it fires on the balance alone, so the same shape as above minus the money is
    # enough, and `PoolStatus#due_on` still answers the rule's date — which is precisely the case
    # the gate has to suppress, because "overdrawn $50.00 · Oct 17" would date a debt with a
    # deadline that belongs to something else.
    it "leaves it off when the pool's own status needs attention" do
      due = Date.current + 2.months
      pool = orphan_with_rule("Late Goal", amount: 300, due: due)
      create(:pool_movement, from_pool: pool, to_pool: checking, amount: 50, date: Date.current)

      visit root_path

      expect(status_line("Late Goal")).to have_content("overdrawn $50.00")
      expect(status_line("Late Goal")).to have_no_content(due.strftime("%b %-d"))
    end
  end

  # The group header is the only thing that says these are unfundable, so it must stay
  # silent when every pool has an account — an empty "No account" heading over nothing
  # is a problem invented out of a healthy screen.
  it "shows no such group when every pool has an account", :aggregate_failures do
    envelope("Groceries", rate: 400)

    visit root_path

    expect(page).to have_css("[data-pool-group='Checking']")
    expect(page).to have_no_css("[data-pool-group='No account']")
    expect(page).to have_no_content("nothing can fund")
  end

  it "names an overdrawn account's buffer as the debt it is", :aggregate_failures do
    fund(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(group("Checking")).to have_content("buffer now -$400.00")
    expect(group("Checking")).to have_css(".text-status-danger", text: "-$400.00")
  end

  # SPEC §8'S ONE ROUGH EDGE, HANDLED WITH WORDING. Rule changes apply immediately — everything in
  # this design is derived — so raising a rule the day after a distribution flips its envelope from
  # `on track` to `behind` with no money missing and nothing having gone wrong. The row says which
  # of the two kinds of `behind` it is.
  #
  # `travel_to` only around the WRITES, never around `visit`: the whole clause is a comparison of
  # two timestamps, and without a controlled clock the rule and the movement are written
  # milliseconds apart and this is a coin toss. The page itself renders at real now, as every other
  # example here does.
  describe "a pool that went behind because a rule was changed" do
    include ActiveSupport::Testing::TimeHelpers

    # EVERY DATE IN THIS BLOCK COMES FROM HERE, resolved ONCE at real now and never inside a
    # `travel_to`. `Date.current` evaluated three hours back is a different day between midnight and
    # 03:00 — and this user is anchored to `Date.current` on a biweekly cadence, so a movement dated
    # a day early falls in the PREVIOUS period, `#latest_distributions` filters it out, and both
    # positive examples fail for three hours a night on a page that is working perfectly. That is
    # the flake class this branch has just finished deleting; it does not get a new member.
    #
    # AND THE PARAGRAPH ABOVE WAS A CLAIM THIS BLOCK DID NOT KEEP, because `let` is LAZY. Nothing
    # read `today` until `accumulating_rule` did, and every example calls that from inside
    # `travel_to(3.hours.ago)` — so the value sworn to be "resolved ONCE at real now" was in fact
    # resolved three hours back, and between 00:00 and 03:00 UTC it was yesterday. The `before`
    # below is what actually resolves it at real now, outside every `travel_to`, exactly as
    # categories/show/pool_card_spec.rb does for its copy of this fixture.
    let(:today) { Date.current }

    before { today }

    def accumulating_rule(name, amount:, priority:)
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
      rule = create(
        :pool_budget,
        pool: pool,
        amount: amount,
        interval_months: 6,
        anchor_date: today + 3.months
      )
      [pool, rule]
    end

    # One allocation per envelope, small enough to leave both of them behind: the clause explains a
    # `behind` row, so the row has to still be behind.
    def distribute(pool, amount, at:)
      travel_to(at) do
        create(
          :pool_movement,
          kind: :allocation,
          from_pool: checking,
          to_pool: pool,
          amount: amount,
          date: today
        )
      end
    end

    # THE PAIR THE CLAUSE HAS TO TELL APART: two envelopes with the same shape of rule, the same
    # distribution and the same `behind` state, differing only in which side of that distribution
    # their rule was last edited on.
    def plant_pair
      deposit(2_000)
      raised_pool = raised_rule = steady_pool = nil

      travel_to(3.hours.ago) do
        raised_pool, raised_rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1)
        steady_pool, = accumulating_rule("Property Tax", amount: 1_200, priority: 2)
      end

      [raised_pool, steady_pool].each { |pool| distribute(pool, 10, at: 2.hours.ago) }
      travel_to(1.hour.ago) { raised_rule.update!(amount: 1_800) }
    end

    # BOTH DIRECTIONS ON ONE SCREEN, and that is the point rather than a convenience. Two envelopes
    # identical in every way that matters — same shape of rule, same distribution, both `behind` —
    # differing only in which side of the distribution their rule was last edited on. Split into
    # two examples, the negative half would pass against a view that never prints the clause at all.
    it "says so on that row and on no other", :aggregate_failures do
      plant_pair

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(row("Property Tax")).to have_content("behind")
      expect(row("Property Tax")).to have_no_content("you changed a rule here after distributing")
    end

    # THE TWO BANDS RENDER THE SAME POOL INCHES APART, and a `behind` envelope is in both by
    # construction. One explaining the state while the other did not would read as the screen
    # disagreeing with itself about why — which is why the clause is threaded through
    # `pool_problem_label` as well as `pool_status_label`.
    it "says the same thing in the attention band" do
      plant_pair

      visit root_path

      expect(find("[data-problem-pool='Car Insurance']"))
        .to have_content("you changed a rule here after distributing")
    end

    # THE CASE THAT WOULD HAVE MADE THE OLD COPY A LIE, and the reason this clause no longer says
    # "you raised this rule". `updated_at` records WHEN a rule moved and nothing about which way:
    # the rule below goes DOWN, from $1,800 to $1,200, and the envelope is still behind against the
    # smaller requirement — so the row fires the clause, and under the old wording told a user who
    # cut their budget that they had raised it. `have_no_content("raised")` is the half that fails
    # if the old string ever comes back.
    it "says a rule changed, not raised, when the rule went down", :aggregate_failures do
      deposit(2_000)
      pool = rule = nil

      travel_to(3.hours.ago) { pool, rule = accumulating_rule("Car Insurance", amount: 1_800, priority: 1) }
      distribute(pool, 10, at: 2.hours.ago)
      travel_to(1.hour.ago) { rule.update!(amount: 1_200) }

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(row("Car Insurance")).to have_no_content("raised")
    end

    # NO DISTRIBUTION, NO CLAUSE. A rule changed on a period nobody has distributed yet has not been
    # changed "after distributing" — the envelope is behind because the money has not been handed
    # out, which is a different sentence and one the row already tells.
    it "stays silent when nothing has been distributed this period", :aggregate_failures do
      deposit(2_000)
      rule = nil

      travel_to(3.hours.ago) { _, rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1) }
      travel_to(1.hour.ago) { rule.update!(amount: 1_800) }

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_no_content("you changed a rule here after distributing")
    end

    # THE CLAUSE BELONGS TO `behind` AND TO NOTHING ELSE. An overdue bill is overdue because it was
    # not paid; an edited rule has nothing to do with it, and the aside would be unexplained noise
    # on the loudest row on the screen. The gate lives in the helper, so this pins it at the
    # render.
    it "stays off a row in another state", :aggregate_failures do
      deposit(2_000)
      pool = payable("Utilities", amount: 120, due: Date.current - 10.days)
      rule = pool.budgets.first

      distribute(pool, 10, at: 2.hours.ago)
      travel_to(1.hour.ago) { rule.update!(amount: 180) }

      visit root_path

      expect(row("Utilities")).to have_content("overdue")
      expect(row("Utilities")).to have_no_content("you changed a rule here after distributing")
    end
  end
end
