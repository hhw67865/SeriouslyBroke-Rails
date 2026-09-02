# frozen_string_literal: true

require "rails_helper"

# HOME'S CATEGORIES BAND — the purpose ledger, rendered (two-ledger spec §2).
#
# This file was `home/pools_spec.rb` and asserted a section per account with that account's
# envelopes nested inside it. There is one band now, over the user's holder categories in fill
# order, headed by AVAILABLE; the accounts band below says only what the bank says. Every figure
# below is the figure the pool-era example asserted, in the shape the model holds it in.
RSpec.describe "Home Categories", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }

  # `sign_in` touches `user` at REAL NOW, which is what keeps `period_anchor_date: Date.current`
  # from being resolved inside a `travel_to` further down this file (CLAUDE.md's third flake cause).
  before do
    checking
    sign_in user, scope: :user
  end

  def band = find("[data-category-band]")

  def account_group(name) = find("[data-account-group='#{name}']")

  def row(name) = find("[data-holding-name='#{name}']")

  # A CATEGORY THAT HOLDS MONEY (spec §3): an expense category with a `funded_since`. A year back,
  # so every entry and allocation this file dates "today" counts against it.
  def holder(name, priority: 1, **attrs)
    create(
      :category,
      :expense,
      user: user,
      name: name,
      priority: priority,
      funded_since: Date.current - 1.year,
      **attrs
    )
  end

  # A rate category: refilled every period, and the shape that reads `left to spend`.
  def envelope(name, rate:, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, pool: nil, category: category, amount: rate)
    end
  end

  # A bill that accumulates toward a date — the shape that reads `on track` while it is being
  # filled on schedule.
  def accumulating(name, amount:, due:, priority: 1, every: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, pool: nil, category: category, amount: amount, interval_months: every, anchor_date: due)
    end
  end

  # A one-off bill with no interval to spread it over.
  def one_off(name, amount:, due:, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, :one_time, pool: nil, category: category, amount: amount, anchor_date: due)
    end
  end

  def deposit(amount)
    category = create(:category, :income, user: user, pool: checking, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # MONEY INTO A CATEGORY IS AN ALLOCATION OUT OF AVAILABLE, and it moves nothing physical (§2) —
  # which is why the account band's figure below never changes when this is called.
  def fund(category, amount, on: Time.zone.now)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  # SPENDING DRAINS THE CATEGORY and the pot at once. The item hangs off the category itself now;
  # the pool era needed a second category pointing at the envelope to reach it.
  def spend(category, amount)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # A rule the user actually pays: an item is the only fulfilment signal BudgetCalculator accepts,
  # and therefore the only way a rule can be late.
  def payable(name, amount:, due:, interval: 1, priority: 1)
    holder(name, priority: priority).tap do |category|
      item = create(:item, category: category, name: "#{name} Bill")
      create(
        :budget,
        pool: nil,
        category: category,
        item: item,
        amount: amount,
        interval_months: interval,
        anchor_date: due
      )
    end
  end

  # THREE MONEY FIGURES FROM THREE MOMENTS, ON ONE SCREEN, and the copy has to keep them apart —
  # which is what this pins. $1,000 of income with $100 already claimed by Groceries leaves the BANK
  # holding $1,000 (an allocation moves nothing physical), AVAILABLE holding $900 now, and $600
  # unclaimed AFTER the $300 this period's rule still wants.
  #
  # Each assertion below includes its time word, so dropping one fails here rather than passing on a
  # substring of the old wording. The pool era had two of these three and shipped both under the
  # bare noun "buffer"; the third arrived with the second ledger.
  it "heads the band with available and the accounts with their own balances", :aggregate_failures do
    deposit(1_000)
    fund(envelope("Groceries", rate: 400), 100)

    visit root_path

    expect(band).to have_content("Groceries")
    expect(band).to have_content("$100.00 left")
    expect(band).to have_content("available now $900.00")
    expect(account_group("Checking")).to have_content("balance now $1,000.00")
    # "target", not "of": a bare "of $2,000.00" never said what the figure measures.
    expect(account_group("Checking")).to have_content("target $2,000.00")
    expect(page).to have_content("$600.00 is still unclaimed after this period")
  end

  # THE ACCOUNT HOLDS NOTHING INSIDE IT ANY MORE. The pool era nested a section's envelopes under
  # its header, so a row was findable inside the account group; a category lives nowhere, and the
  # account band has exactly one thing to say.
  it "keeps the categories out of the accounts band", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(band).to have_content("Groceries")
    expect(account_group("Checking")).to have_no_content("Groceries")
    expect(page).to have_no_css("[data-account-group='No account']")
    expect(page).to have_no_content("nothing can fund")
  end

  it "shows a balance on an on-track category" do
    deposit(2_000)
    fund(accumulating("Rent", amount: 2_000, due: Date.current + 2.months), 2_000)

    visit root_path

    expect(row("Rent")).to have_content("$2,000.00 · on track")
  end

  # Principle 2 on the row that used to break it: a goal with no dated rule could reach no state but
  # `left to spend`, so a vacation fund rendered "$424.00 left" — a spendable number for money that
  # is not spendable.
  it "shows a savings goal saving toward its target, never as money to spend", :aggregate_failures do
    goal = holder("Vacation", target_amount: 2_400)
    deposit(500)
    fund(goal, 424)

    visit root_path

    expect(row("Vacation")).to have_content("$424.00 of $2,400.00")
    expect(row("Vacation")).to have_no_content("left")
    # Accumulating on plan is not trouble, so it stays one quiet line.
    expect(row("Vacation")["data-expanded"]).to eq("false")
  end

  it "auto-expands a category that needs attention", :aggregate_failures do
    one_off("Dentist", amount: 300, due: Date.current + 3.days)

    visit root_path

    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Dentist")).to have_content("won't make it")
    # The auto-expand exists to show the rule behind the trouble. A `data-expanded` flag over an
    # empty row would satisfy the attribute and none of the point.
    expect(row("Dentist")).to have_css("[data-role='holding-detail']")
    expect(row("Dentist")).to have_content("$300.00")
    expect(row("Dentist")).to have_content((Date.current + 3.days).strftime("%b %-d"))
  end

  # The two states that render a date the user has to act on, seen through a real row — which is
  # where the date and the rule beneath it actually meet.
  it "shows an overdue category with the date that passed and the rule behind it", :aggregate_failures do
    payable("Utilities", amount: 120, due: Date.current - 10.days)

    visit root_path

    expect(row("Utilities")).to have_content("overdue · was #{(Date.current - 10.days).strftime("%b %-d")}")
    expect(row("Utilities")["data-expanded"]).to eq("true")
    expect(row("Utilities")).to have_content("Utilities Bill")
    expect(row("Utilities")).to have_content("$120.00 · #{(Date.current - 10.days).strftime("%b %-d")}")
  end

  # The lag is a function of how many boundaries fall inside the cycle, so the figure is matched by
  # shape rather than pinned to a date arithmetic this example does not own.
  it "shows a behind category with the rule it is behind on", :aggregate_failures do
    accumulating("Car Insurance", amount: 1_200, due: Date.current + 3.months, every: 6)

    visit root_path

    expect(row("Car Insurance")).to have_content(/behind \$\d[\d,]*\.\d\d/)
    expect(row("Car Insurance")["data-expanded"]).to eq("true")
    expect(row("Car Insurance")).to have_content("Every 6 months")
    expect(row("Car Insurance")).to have_content("$1,200.00 · #{(Date.current + 3.months).strftime("%b %-d")}")
  end

  # `rules.empty?` does NOT imply a rate rule exists. A category with no rules at all and a negative
  # holding reaches :overdrawn — the only state guarded on the balance alone — and expands, so the
  # fallback sentence has to be true of what is actually there. Both halves, because a sentence that
  # is right in one shape and false in the other is pinned by neither.
  it "explains an overdrawn rate category by its rate", :aggregate_failures do
    deposit(200)
    dining = envelope("Dining Out", rate: 150)
    fund(dining, 100)
    spend(dining, 180)

    visit root_path

    expect(row("Dining Out")).to have_content("overdrawn $80.00")
    expect(row("Dining Out")).to have_content("refills at its rate")
    expect(row("Dining Out")).to have_no_content("nothing fills it")
  end

  it "says so plainly when an overdrawn category has no rules at all", :aggregate_failures do
    mystery = holder("Mystery")
    spend(mystery, 80)

    visit root_path

    expect(row("Mystery")).to have_content("overdrawn $80.00")
    expect(row("Mystery")).to have_content("nothing fills it")
    # The refill promise would be a flat untruth here: nothing fills this category.
    expect(row("Mystery")).to have_no_content("refills at its rate")
  end

  # Plan 2b decision 1, on the row it changes. An expired rate category's leftover is still
  # physically there until a distribution moves it, and both partitions of one total (§2) are the
  # invariant the app rests on. So the real holding renders, marked as belonging to a period that is
  # over.
  #
  # Both categories on ONE screen, at the identical holding and the identical rule, differing only in
  # which side of a period boundary their money arrived on. Split into two examples the negative half
  # would pass against a view that never says "last period" at all.
  it "marks a rate category whose period has ended, and only that one", :aggregate_failures do
    deposit(1_000)
    fund(envelope("Groceries", rate: 400, priority: 1), 60, on: Date.current - 20.days)
    fund(envelope("Dining Out", rate: 400, priority: 2), 60, on: Date.current)

    visit root_path

    expect(row("Groceries")).to have_content("$60.00 left · last period")
    expect(row("Dining Out")).to have_content("$60.00 left")
    expect(row("Dining Out")).to have_no_content("last period")
  end

  it "leaves a quiet category collapsed", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(row("Groceries")["data-expanded"]).to eq("false")
    # The other half of the same rule: a quiet row renders its one line and nothing else.
    expect(row("Groceries")).to have_no_css("[data-role='holding-detail']")
  end

  # Two categories, one of each kind, on the same screen: the auto-expanded rows have to be EXACTLY
  # the ones needing attention. Either half alone passes against a view that expands everything, or
  # nothing.
  it "expands only the rows that need attention", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)
    one_off("Dentist", amount: 300, due: Date.current + 3.days, priority: 2)

    visit root_path

    expect(page).to have_css("[data-expanded='true']", count: 1)
    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Groceries")["data-expanded"]).to eq("false")
  end

  # ── DELETED (Task 6): "gives a pool with no account a group of its own" and "shows no such group
  # when every pool has an account". The orphan band, `home/_orphans` and its "nothing can fund it"
  # copy are gone with the concept — a category belongs to no account and needs none, because
  # allocating money moves nothing physical (§2). The negative half survives as the last two
  # assertions of "keeps the categories out of the accounts band", where an absent band is still
  # worth stating.

  # THE EMPTY STATE, which is new: a user whose categories hold nothing has a band with no rows, and
  # a blank panel on a money screen reads as data that failed to load.
  it "says so plainly when no category holds money yet", :aggregate_failures do
    deposit(400)
    create(:category, :expense, user: user, name: "Someday")

    visit root_path

    expect(band).to have_content("No category holds money yet")
    expect(band).to have_link("Give one a rule on the Budget page", href: budget_page_path)
    expect(band).to have_no_content("Someday")
  end

  # ** THE DUE DATE ON A QUIET ROW — the shape a byte-for-byte diff of Home could not see. **
  #
  # The row's date clause gates on the STATUS being quiet, not on the ROW being quiet, and the two
  # were briefly the same question. `pool_status_label` knows nothing about the row's other flags, so
  # "the label already said the date" — which makes the gate safe for attention rows — is false on a
  # quiet one, and a category reading `$300.00 · on track · Oct 17` lost the only date on its line.
  #
  # Scoped to `span.text-sm`, which is the status line: the detail underneath a row prints every
  # dated rule's own date, so `have_no_content(date)` against the whole row would fail on text that
  # is supposed to be there.
  describe "a quiet category's due date", :aggregate_failures do
    def status_line(name) = find("[data-holding-name='#{name}'] span.text-sm")

    # A TARGET-BEARING category with an ANCHORED rule: the anchor is what takes it out of the
    # `saving` state (`HoldingCalculator#dateless_goal?` requires no anchored rule) and into the
    # quiet `on track` one, which is the only quiet state carrying a date.
    def goal_with_rule(name, amount:, due:)
      holder(name, target_amount: 5_000).tap do |category|
        create(:budget, pool: nil, category: category, amount: amount, interval_months: 1, anchor_date: due)
      end
    end

    it "prints it when the category's own status is quiet" do
      due = Date.current + 2.months
      category = goal_with_rule("Old Goal", amount: 300, due: due)
      fund(category, 300)

      visit root_path

      expect(status_line("Old Goal")).to have_content("on track")
      expect(status_line("Old Goal")).to have_content(due.strftime("%b %-d"))
    end

    # The other direction, on a category whose OWN status needs attention. Overdrawn is the state to
    # reach it with: it fires on the holding alone, and `HoldingStatus#due_on` still answers the
    # rule's date — which is precisely the case the gate has to suppress, because "overdrawn $50.00 ·
    # Oct 17" would date a debt with a deadline that belongs to something else.
    it "leaves it off when the category's own status needs attention" do
      due = Date.current + 2.months
      category = goal_with_rule("Late Goal", amount: 300, due: due)
      spend(category, 50)

      visit root_path

      expect(status_line("Late Goal")).to have_content("overdrawn $50.00")
      expect(status_line("Late Goal")).to have_no_content(due.strftime("%b %-d"))
    end
  end

  # AN OVERDRAWN ACCOUNT IS A PHYSICAL FACT, and this is the band that owns the number. It takes
  # SPENDING to reach it now, not an allocation: money claimed by a category has not left the bank.
  it "names an overdrawn account's balance as the debt it is", :aggregate_failures do
    spend(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(account_group("Checking")).to have_content("balance now -$400.00")
    expect(account_group("Checking")).to have_css(".text-status-danger", text: "-$400.00")
  end

  # SPEC §8'S ONE ROUGH EDGE, HANDLED WITH WORDING. Rule changes apply immediately — everything in
  # this design is derived — so raising a rule the day after a distribution flips its category from
  # `on track` to `behind` with no money missing and nothing having gone wrong. The row says which of
  # the two kinds of `behind` it is.
  #
  # `travel_to` only around the WRITES, never around `visit`: the whole clause is a comparison of two
  # timestamps, and without a controlled clock the rule and the allocation are written milliseconds
  # apart and this is a coin toss.
  describe "a category that went behind because a rule was changed" do
    include_context "with a rule changed after the money went out"

    # EVERY DATE IN THIS BLOCK COMES FROM THE SHARED CONTEXT, resolved ONCE at real now and never
    # inside a `travel_to`. `#allocate` is the context's PURPOSE-LEDGER arm — `DistributionClock`
    # reads `Allocation.distributed` since Task 6, and its pool-era `#distribute` twin is deleted
    # with the `account_ids:` surface that made it necessary.
    def accumulating_rule(name, amount:, priority:)
      category = holder(name, priority: priority)
      rule = create(
        :budget,
        pool: nil,
        category: category,
        amount: amount,
        interval_months: 6,
        anchor_date: today + 3.months
      )
      [category, rule]
    end

    # THE PAIR THE CLAUSE HAS TO TELL APART: two categories with the same shape of rule, the same
    # distribution and the same `behind` state, differing only in which side of that distribution
    # their rule was last edited on.
    def plant_pair
      deposit(2_000)
      raised = raised_rule = steady = nil

      before_distributing do
        raised, raised_rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1)
        steady, = accumulating_rule("Property Tax", amount: 1_200, priority: 2)
      end

      # One allocation per category, small enough to leave both of them behind: the clause explains a
      # `behind` row, so the row has to still be behind.
      [raised, steady].each { |category| allocate(category, 10) }
      after_distributing { raised_rule.update!(amount: 1_800) }
    end

    # BOTH DIRECTIONS ON ONE SCREEN, and that is the point rather than a convenience. Split into two
    # examples, the negative half would pass against a view that never prints the clause at all.
    it "says so on that row and on no other", :aggregate_failures do
      plant_pair

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(row("Property Tax")).to have_content("behind")
      expect(row("Property Tax")).to have_no_content("you changed a rule here after distributing")
    end

    # THE TWO BANDS RENDER THE SAME CATEGORY INCHES APART, and a `behind` category is in both by
    # construction. One explaining the state while the other did not would read as the screen
    # disagreeing with itself about why — which is why the clause is threaded through
    # `pool_problem_label` as well as `pool_status_label`.
    it "says the same thing in the attention band" do
      plant_pair

      visit root_path

      expect(find("[data-problem-category='Car Insurance']"))
        .to have_content("you changed a rule here after distributing")
    end

    # THE CASE THAT WOULD HAVE MADE THE OLD COPY A LIE, and the reason this clause no longer says
    # "you raised this rule". `updated_at` records WHEN a rule moved and nothing about which way: the
    # rule below goes DOWN, from $1,800 to $1,200, and the category is still behind against the
    # smaller requirement.
    it "says a rule changed, not raised, when the rule went down", :aggregate_failures do
      deposit(2_000)
      category = rule = nil

      before_distributing { category, rule = accumulating_rule("Car Insurance", amount: 1_800, priority: 1) }
      allocate(category, 10)
      after_distributing { rule.update!(amount: 1_200) }

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_content("you changed a rule here after distributing")
      expect(row("Car Insurance")).to have_no_content("raised")
    end

    # NO DISTRIBUTION, NO CLAUSE. A rule changed on a period nobody has distributed yet has not been
    # changed "after distributing" — the category is behind because the money has not been handed
    # out, which is a different sentence and one the row already tells.
    it "stays silent when nothing has been distributed this period", :aggregate_failures do
      deposit(2_000)
      rule = nil

      before_distributing { _, rule = accumulating_rule("Car Insurance", amount: 1_200, priority: 1) }
      after_distributing { rule.update!(amount: 1_800) }

      visit root_path

      expect(row("Car Insurance")).to have_content("behind")
      expect(row("Car Insurance")).to have_no_content("you changed a rule here after distributing")
    end

    # THE CLAUSE BELONGS TO `behind` AND TO NOTHING ELSE. An overdue bill is overdue because it was
    # not paid; an edited rule has nothing to do with it, and the aside would be unexplained noise on
    # the loudest row on the screen. The gate lives in the helper, so this pins it at the render.
    it "stays off a row in another state", :aggregate_failures do
      deposit(2_000)
      category = payable("Utilities", amount: 120, due: Date.current - 10.days)
      rule = category.budgets.first

      allocate(category, 10)
      after_distributing { rule.update!(amount: 180) }

      visit root_path

      expect(row("Utilities")).to have_content("overdue")
      expect(row("Utilities")).to have_no_content("you changed a rule here after distributing")
    end
  end
end
