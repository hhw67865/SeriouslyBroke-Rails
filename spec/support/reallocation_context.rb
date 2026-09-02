# frozen_string_literal: true

# THE FIXTURE THE REALLOCATION SCREENS ARE MEASURED AGAINST — one Checking account carrying one
# envelope per shape the screen has to say something different about, plus a second account that
# must never appear.
#
# Shared because the reallocation specs are SPLIT ACROSS FOUR FILES, matching this project's
# page-based test structure — `feature/page/section_spec.rb` — which one flat file of twenty-nine
# examples was not.
#
# THE SPLIT IS NOT WHAT FIXED THE CHROMEDRIVER CRASHES, and that is worth writing down because I
# reached three conclusions here and the first two were wrong.
#
# `Selenium::WebDriver::Error::InvalidSessionIdError`, zero assertion failures, a varying block of
# examples each run. I blamed the environment (the plan documents exactly this crash elsewhere);
# then, when `spec/system/distributions/confirm_spec.rb` ran clean at the same moment, I blamed the
# example count, because each group passed alone while the twenty-nine together crashed three runs
# in four. Splitting the file did not stop it: the six-example `new/sources_spec.rb` then failed
# four-of-six on three consecutive runs.
#
# The cause was in the spec. `spec/support/capybara.rb` quits the driver after EVERY example, and
# `new/sources_spec.rb` held the one example body in these files that touched Capybara not at all —
# a pair of ledger assertions under a bare `visit`. It finished before the page settled, the quit
# raced it, and the wedged driver poisoned every session after it in the process. Adding one page
# assertion to that body took the file from 4-of-6 failing on three consecutive runs to three
# consecutive clean ones.
#
# So: an example that asserts only against the database still has to be anchored to the screen it
# is about. And when reading a red here, check the error class first — `InvalidSessionIdError` is
# the browser dying rather than the app, but it is not automatically somebody else's problem.
#
# All figures exact, and every envelope but Coffee funded today so nothing sweeps:
#
#   Checking buffer   $810   no rules                        free $810
#   Dentist             $0   $300 due in 3 days, unreachable free   $0   won't make it
#   Car             $1,000   $800 Maintenance due in 56 days free $200   on track
#   Insurance         $400   $400 Premium due in 3 days      free   $0   on track
#   Gas                $40   $150 a period rate rule         free   $0
#   Rent              $100   $2,000 Rent Bill due in 40 days free   $0
#   Cushion           $500   savings goal, no rules          free $500
#   Coffee            $150   $100 a period, funded a fortnight ago — its period has CLOSED
#   Ally / Holiday      $0   a second account entirely
#
# THE INVARIANT IS `Σ pools == your bank balance`, and a reallocation cannot change it: the money
# stays in the account, so the bank holds exactly what it held. Every total is pinned against the
# LITERAL $3,000 deposit below rather than against a sum of the app's own parts — `Pool#total` IS
# that sum, so summing the parts against it is `x == x` and passes after any write whatsoever.
RSpec.shared_context "with a Checking account to reallocate in" do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:dentist) { pool("Dentist") }
  let(:car) { pool("Car") }

  before do
    sign_in user, scope: :user
    deposit(3_000)
    dated_rule(envelope("Dentist", priority: 1), "Dental Work", 300, due_in: 3)
    dated_rule(envelope("Car", priority: 2, funded: 1_000), "Maintenance", 800, due_in: 56)
    dated_rule(envelope("Insurance", priority: 3, funded: 400), "Premium", 400, due_in: 3)
    rate_rule(envelope("Gas", priority: 4, funded: 40), 150)
    dated_rule(envelope("Rent", priority: 5, funded: 100), "Rent Bill", 2_000, due_in: 40)
    savings("Cushion", funded: 500)
    closed_envelope("Coffee", rate: 100, funded: 150)
    other_account
  end

  # A SYNCHRONISATION POINT, NOT AN EXPECTATION: a hook doing two round trips has to wait for the
  # first to land, and Capybara's predicates are what block until it does.
  def await(content)
    return if page.has_content?(content)

    raise "expected the page to show #{content.inspect} before the next step"
  end

  # The one route a cross-account or foreign source can reach `create` by, since the screen never
  # renders a radio for either: the real form, with one field's value hand-edited. Clicked first,
  # because changing a radio's value does not check it.
  def submit_with_source(target)
    find_by_id("from-#{car.id}").click
    page.execute_script("document.getElementById('from-#{car.id}').value = '#{target.id}'")
    click_on "Move the money"
  end

  def pool(name) = user.pools.find_by!(name: name)

  # A FRESHLY BUILT calculator every time: PoolCalculator memoises and is stale-after-write by
  # construction, so one held across a move answers from before it.
  def balance_of(name) = Pool.find(pool(name).id).calculator.balance

  # WHAT THE BANK WOULD SAY: the account's own cash plus every pool inside it, compared against
  # the literal deposit the fixture planted and never against a sum of its own parts.
  def bank_balance = Pool.find(checking.id).total

  def envelope(name, priority:, funded: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    fund(pool, funded)
    pool
  end

  def savings(name, funded:)
    pool = create(
      :pool,
      :savings_pool,
      user: user,
      account: checking,
      name: name,
      target_amount: 5_000,
      priority: 6
    )
    fund(pool, funded)
    pool
  end

  def fund(pool, amount)
    return if amount.zero?

    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: Date.current)
  end

  # A one-time dated rule with a payable item, so BudgetCalculator has a real fulfilment signal
  # and `interval_months: nil` keeps :behind out of the picture — a cycle it has no interval to
  # spread over cannot put the pool behind schedule, which keeps every figure here exact.
  def dated_rule(pool, item_name, amount, due_in:)
    category = create(:category, :expense, user: user, pool: pool)
    create(
      :pool_budget,
      pool: pool,
      item: create(:item, category: category, name: item_name),
      amount: amount,
      interval_months: nil,
      anchor_date: Date.current + due_in
    )
  end

  def rate_rule(pool, amount)
    create(:pool_budget, :per_period_rate, pool: pool, amount: amount)
  end

  # An envelope funded a fortnight ago — one biweekly boundary back — so its rate period has closed
  # and PoolCalculator#period_closed? is true. The whole of its leftover is what the next
  # distribution sweeps back, which is the shape `net_of_sweep:` exists for.
  def closed_envelope(name, rate:, funded:)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: 7)
    create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14)
    pool
  end

  def other_account
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:pool, :budget_pool, user: user, account: ally, name: "Holiday", priority: 1)
  end

  def deposit(amount)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end
end
