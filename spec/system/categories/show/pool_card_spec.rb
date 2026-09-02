# frozen_string_literal: true

require "rails_helper"

# THE POOL CARD SAYS WHAT ITS POOL IS — §7a's savings-chrome family, its last known member.
#
# Before this, the card rendered savings chrome for every pool it was handed: a budget envelope
# read "Savings Pool" with a bare "Target:" and no figure, and an ACCOUNT read
# "Savings Pool / Target: $1,000.00 / -30% complete" — a savings progress bar drawn on a buffer,
# in red, reproduced below from the shape this app's own demo data holds.
#
# `Capybara.exact` IS UNSET IN THIS SUITE and this page is dense with strings that contain the ones
# under test: the budget block directly above the card also says "Envelope", the savings summary
# card also says "Savings Pool", the banner and the header print the CATEGORY's name, and the
# sidebar says "Pools". Every assertion is therefore scoped to `[data-pool-card]`, and every
# positive is paired with a negative — an unscoped `have_content("Savings Pool")` on a savings
# category's page passes whatever this card renders.
RSpec.describe "Categories Show - Pool card", type: :system do
  let(:today) { Date.current }
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before do
    today # OUTSIDE any travel_to, so no example can date its own fixtures against a frozen clock.
    sign_in user, scope: :user
  end

  def card = find("[data-pool-card]")

  def envelope(name, rate: 400)
    create(:pool, :budget_pool, user: user, account: checking, name: name).tap do |pool|
      create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
    end
  end

  def fund(pool, amount, on: Date.current)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def pointed_at(pool, type: :expense)
    create(:category, type, user: user, name: "#{pool.name} Spending", pool: pool)
  end

  # ------------------------------------------------------------------------------------------
  # A savings pool — one noun, and the verb the category earns
  # ------------------------------------------------------------------------------------------

  # THE CATEGORY IS AN EXPENSE ONE (plan 3, task 5). It was a SAVINGS category, which is not a type
  # any more; every noun, figure and negative below is unchanged, because this card asks the POOL's
  # type for its words and only its closing sentence ever asked the category's.
  describe "a category pointing at a savings pool" do
    let(:goal) { create(:pool, user: user, name: "Emergency Fund", target_amount: 2_000) }

    before do
      create(:category, :expense, user: user, name: "Emergency Fund Saving", pool: goal)
      create(:pool_movement, from_pool: checking, to_pool: goal, amount: 500, date: Date.current)
      visit category_path(user.categories.find_by!(name: "Emergency Fund Saving"))
    end

    # CHANGED WITH THE ONE NAMER (2d whole-plan review, fix 2). This pinned "Savings Pool" and
    # "View Savings Pool", which were this card's private nouns for a pool the budget block above
    # called an "Envelope" and the entry form's impact card called a "goal" — three words, one
    # pool, and the classifiers agreeing throughout. `Pool::NOUNS` is now the single mapping and
    # the impact card's vocabulary is the one that won, because it was already the app's ("buffer
    # now" on Home, `#dateless_goal?` on the calculator, §7.1's buffer marker).
    it "calls itself a goal, with its target and its progress", :aggregate_failures do
      expect(card["data-pool-card-type"]).to eq("savings")
      expect(card).to have_content("Goal")
      expect(card).to have_content("Target: $2,000.00")
      expect(card).to have_content("25% complete")
      expect(card).to have_link("View Goal")
      expect(card).to have_no_content("Savings Pool")
    end

    # The negative half, and it is not decoration: the type test could have been written the wrong
    # way round and every positive above would still pass on some other arm.
    it "does not borrow the envelope's or the buffer's words", :aggregate_failures do
      expect(card).to have_no_content("Envelope")
      expect(card).to have_no_content("Buffer")
      expect(card).to have_no_content("buffer now")
    end

    # THE VERB NO LONGER BRANCHES (plan 3, task 5). Fix 2 split it — "contributes to" for a savings
    # category, "draws from" for an expense one — and only the second arm is reachable now: money
    # ARRIVES in a goal as a `PoolMovement`, which no category is party to. Both directions here:
    # the surviving sentence is on screen and the retired one is not.
    it "says the category draws from the goal, and never that it contributes", :aggregate_failures do
      expect(card).to have_content("This category's spending draws from a shared goal")
      expect(card).to have_content("money is moved into it rather than spent into it")
      expect(card).to have_no_content("contributes to")
    end
  end

  # ------------------------------------------------------------------------------------------
  # An EXPENSE category pointing at a savings pool — the shape the three nouns diverged on
  # ------------------------------------------------------------------------------------------

  # THE DEMO'S OWN SHAPE, not a corner: Health → Emergency Fund and Education → Retirement
  # Supplement both point an expense category at a savings goal. Before this fix the page said
  # "Envelope" in the budget block, "Savings Pool" on this card and "contributes to" in its
  # sentence — while `PoolBalanceLedger::ENTRY_POOL_ID` SUBTRACTS that category's entries from the
  # pool and `EntryImpactPresenter#direction` signs them -1 on the entry form. The card was naming
  # the wrong thing and the wrong direction at once.
  describe "an expense category pointing at a savings pool" do
    before do
      goal = create(:pool, user: user, name: "Retirement Supplement", target_amount: 2_000)
      create(:pool_movement, from_pool: checking, to_pool: goal, amount: 500, date: Date.current)
      pointed_at(goal)
      visit category_path(user.categories.find_by!(name: "Retirement Supplement Spending"))
    end

    it "calls the pool a goal and says the category DRAWS from it", :aggregate_failures do
      expect(card["data-pool-card-type"]).to eq("savings")
      expect(card).to have_content("Goal")
      expect(card).to have_content("This category's spending draws from a shared goal")
      expect(card).to have_no_content("This category contributes to")
      expect(card).to have_no_content("Savings Pool")
    end

    # THE THREE CARDS AGREEING, ON ONE PAGE, WHICH IS THE WHOLE OF FIX 2. The budget block sits
    # four inches above this card and used to say "Envelope" about the same pool. Asserted
    # page-wide rather than in the card's scope, because "the page says one noun" is the claim.
    it "makes the budget block above it use the same noun", :aggregate_failures do
      block = find("[data-budget-block]")

      expect(block).to have_content("Goal")
      expect(block).to have_no_content("Envelope")
      expect(find("[data-envelope-name]")).to have_content("Retirement Supplement")
    end
  end

  # ------------------------------------------------------------------------------------------
  # A budget envelope — "Savings Pool / Target:" with nothing after it
  # ------------------------------------------------------------------------------------------

  describe "a category pointing at a budget envelope" do
    before do
      pointed_at(envelope("Groceries"))
      fund(user.pools.find_by!(name: "Groceries"), 250)
      visit category_path(user.categories.find_by!(name: "Groceries Spending"))
    end

    # UNCHANGED BY THE ONE NAMER, and that is the assertion: "envelope" is what a budget pool was
    # already called here and on the two screens beside it, so `Pool::NOUNS` had to leave this arm
    # exactly where it stood while moving the savings one.
    it "names itself an envelope and says how it is doing, in the row vocabulary", :aggregate_failures do
      expect(card["data-pool-card-type"]).to eq("budget")
      expect(card).to have_content("Envelope")
      expect(card).to have_content("$250.00 left")
      expect(card).to have_link("View Envelope")
      expect(card).to have_no_content("Goal")
    end

    # THE DEFECT, ASSERTED AS ITSELF. A budget envelope has no `target_amount` at all, which is how
    # "Target:" came to print with nothing after it — a label with a missing figure reads as data
    # that failed to load, on a card whose heading was also wrong.
    it "drops the savings chrome entirely", :aggregate_failures do
      expect(card).to have_no_content("Savings Pool")
      expect(card).to have_no_content("Target:")
      expect(card).to have_no_content("% complete")
      # The savings sentence in BOTH of its directions — the noun changed under this assertion
      # (fix 2) and a stale literal here would have gone on passing against a string the app no
      # longer prints anywhere.
      expect(card).to have_no_content("contributes to a shared goal")
      expect(card).to have_no_content("draws from a shared goal")
    end
  end

  # ------------------------------------------------------------------------------------------
  # Both label suffixes, threaded by the shared row shape
  # ------------------------------------------------------------------------------------------

  # THE CARD IS A NEW CALLER OF THE ROW VOCABULARY, which is the exact method 2c's whole-plan review
  # caught two callers dropping a suffix from. It cannot repeat that here because it passes an
  # OBJECT to `shared/_holding_status` rather than two optional keywords — but "cannot" is a claim, so
  # both suffixes are asserted in both directions.
  describe "the label's two suffixes" do
    # The changed-after-distributing half of this block runs on the shared clock (plan 3, task 6);
    # its `today` is this file's own, resolved identically and forced outside every `travel_to` by
    # the outer `before` as well as by the context's.
    include_context "with a rule changed after the money went out"

    it "marks an envelope whose period has ended" do
      pointed_at(envelope("Groceries"))
      fund(user.pools.find_by!(name: "Groceries"), 60, on: today - 20.days)

      visit category_path(user.categories.find_by!(name: "Groceries Spending"))

      expect(card).to have_content("$60.00 left · last period")
    end

    # The negative half on the identical shape — same envelope, same rule, same balance, differing
    # only in which side of the period boundary the money arrived on.
    it "leaves a live period unmarked", :aggregate_failures do
      pointed_at(envelope("Groceries"))
      fund(user.pools.find_by!(name: "Groceries"), 60, on: today)

      visit category_path(user.categories.find_by!(name: "Groceries Spending"))

      expect(card).to have_content("$60.00 left")
      expect(card).to have_no_content("last period")
    end

    # `changed_after_distributing:` is the second suffix and it needs a `behind` envelope — a rate
    # rule is `left to spend` however little is in it, so this one accumulates toward a date.
    #
    # THE RULE CARRIES BOTH OWNERS (Task 6), and that pair is what this screen is mid-transition
    # between: the card still reads the POOL's status, while `CategoryBudgetPresenter
    # #changed_after_distributing?` asks `DistributionClock`'s CATEGORY arm — the pool-era arm went
    # with its `account_ids:` surface, because there is one root and one distribution per period now
    # (two-ledger spec §2). `Budget#must_have_an_owner` accepts either owner and Task 1's migration
    # wrote both onto every migrated rule, so this is the shape real data is in. Task 7 moves the
    # rest of the card and the pool half goes with it.
    def accumulating(name, amount:)
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name)
      category = pointed_at(pool)
      rule = create(
        :pool_budget,
        pool: pool,
        category: category,
        amount: amount,
        interval_months: 6,
        anchor_date: today + 3.months
      )
      [pool, category, rule]
    end

    it "says a rule changed after the money went out" do
      category = rule = nil
      before_distributing { _, category, rule = accumulating("Car Insurance", amount: 1_200) }
      allocate(category, 10)
      after_distributing { rule.update!(amount: 1_800) }

      visit category_path(user.categories.find_by!(name: "Car Insurance Spending"))

      expect(card).to have_content("you changed a rule here after distributing")
    end

    # The same envelope, the same distribution, the rule never touched afterwards. Without this the
    # positive above would pass against a card that printed the clause unconditionally.
    it "stays silent when the rule was not touched afterwards", :aggregate_failures do
      category = nil
      before_distributing { _, category, = accumulating("Car Insurance", amount: 1_200) }
      allocate(category, 10)

      visit category_path(user.categories.find_by!(name: "Car Insurance Spending"))

      expect(card).to have_content("behind")
      expect(card).to have_no_content("you changed a rule here after distributing")
    end
  end

  # ------------------------------------------------------------------------------------------
  # An account — the worst case, reproduced
  # ------------------------------------------------------------------------------------------

  describe "a category pointing at an account" do
    before do
      buffer = create(:pool, :account, user: user, name: "Side Gig Checking", target_amount: 1_000)
      create(:pool_movement, from_pool: buffer, to_pool: envelope("Groceries"), amount: 300, date: Date.current)
      pointed_at(buffer)
      visit category_path(user.categories.find_by!(name: "Side Gig Checking Spending"))
    end

    it "calls itself the buffer and prints what is in it", :aggregate_failures do
      expect(card["data-pool-card-type"]).to eq("account")
      expect(card).to have_content("Buffer")
      expect(card).to have_content("buffer now -$300.00")
      expect(card).to have_link("View Account")
    end

    # THE EXACT SHAPE FOUND IN TASK 5'S FIX ROUND, on this app's own demo: an account with a buffer
    # marker of $1,000 and $300 of overdraft rendered "Savings Pool / Target: $1,000.00 / -30%
    # complete" — a progress bar measuring an overdrawn buffer against a goal it is not saving
    # toward. `-30%` is asserted as a literal because that is the figure that was on screen.
    it "draws no savings progress on a buffer, target or no target", :aggregate_failures do
      expect(card).to have_no_content("Savings Pool")
      expect(card).to have_no_content("Target:")
      expect(card).to have_no_content("% complete")
      expect(card).to have_no_content("-30")
      expect(card).to have_no_css("[style*='width:']")
    end
  end

  # ------------------------------------------------------------------------------------------
  # The start-date bound on the card's own sentence
  # ------------------------------------------------------------------------------------------

  # THE SENTENCE USED TO PROMISE MORE THAN THE LEDGER DELIVERS. "This category's spending comes out
  # of this envelope", stated in the present tense with no date on it, was true until the start-date
  # rule (main-account spec §3) landed: an envelope counts its categories' spending only from its
  # own `start_date` on, and everything earlier reads against the user's MAIN account. The card was
  # naming the envelope for all of it — the same unbounded promise the Budget page's re-point clause
  # was flipped for, on a smaller surface.
  #
  # THE DATE IS A PLANTED LITERAL, never read back off the pool under test. `Jun 1, 2025` is written
  # into the fixture and asserted as a string, so an example cannot pass by printing whatever date
  # the record happens to hold — which is what `pool.start_date.strftime(...)` on both sides would
  # be. The factory's own `start_date` is a year back from the run day and would drift with it.
  #
  # ALL THREE ARMS, because the bound is not uniform: an envelope and a goal both take it, and an
  # ACCOUNT takes none at all — a date gate on the buffer would invent a limit the ledger does not
  # apply, so its paragraph must stay bare. The third example is the one that would catch a clause
  # pasted into every branch.
  describe "the start date its sentence is bounded by" do
    def dated(pool) = pool.tap { |record| record.update!(start_date: Date.new(2025, 6, 1)) }

    it "bounds the envelope sentence and names the day", :aggregate_failures do
      pointed_at(dated(envelope("Groceries")))
      visit category_path(user.categories.find_by!(name: "Groceries Spending"))

      expect(card).to have_content("comes out of this envelope from Jun 1, 2025 onward")
      expect(card).to have_content("spending before then stays with your main account")
    end

    it "bounds the goal sentence the same way", :aggregate_failures do
      goal = dated(create(:pool, user: user, name: "Emergency Fund", target_amount: 2_000))
      pointed_at(goal)
      visit category_path(user.categories.find_by!(name: "Emergency Fund Spending"))

      expect(card).to have_content("draws from a shared goal, from Jun 1, 2025 onward")
      expect(card).to have_content("spending before then stays with your main account")
    end

    it "leaves the account sentence unbounded, because an account has no date gate", :aggregate_failures do
      pointed_at(dated(create(:pool, :account, user: user, name: "Side Gig Checking")))
      visit category_path(user.categories.find_by!(name: "Side Gig Checking Spending"))

      expect(card).to have_content("an account is your buffer")
      expect(card).to have_no_content("Jun 1, 2025")
      expect(card).to have_no_content("stays with your main account")
    end
  end
end
