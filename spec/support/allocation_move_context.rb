# frozen_string_literal: true

# THE FIXTURE THE REALLOCATION SCREENS ARE MEASURED AGAINST, on the purpose ledger (two-ledger spec
# §2) — one category per shape the screen has to say something different about, plus the root they
# are all funded out of.
#
# THE PORT OF `spec/support/reallocation_context.rb`, FIGURE FOR FIGURE. That context is still
# standing for the pool-era screen Home links to until Task 6, and it goes with it.
#
# WHAT COULD NOT COME ACROSS: the second account and its Holiday envelope. Nothing crosses anything
# on the purpose ledger — an allocation moves intention, not location — so "a pool in another
# account, which must never appear" is not a shape any more. Every one of the user's holder
# categories is offered, always.
#
# Shared because the reallocation specs are SPLIT ACROSS FOUR FILES, matching this project's
# page-based test structure — `feature/page/section_spec.rb`.
#
# AN EXAMPLE THAT ASSERTS ONLY AGAINST THE DATABASE STILL HAS TO BE ANCHORED TO THE SCREEN IT IS
# ABOUT, and that is this context's hardest-won note. `spec/support/capybara.rb` quits the driver
# after EVERY example, and a body that touches Capybara not at all under a bare `visit` finishes
# before the page settles, races the quit, and wedges the driver for every example after it in the
# process — `InvalidSessionIdError`, zero assertion failures, a varying block of failures each run.
# One page assertion in the body fixes it. When reading a red here, check the error class first.
#
# All figures exact, and every category but Coffee funded today so nothing sweeps:
#
#   Available         $810   the root; no rules can hold it   free $810
#   Dentist             $0   $300 due in 3 days, unreachable  free   $0   won't make it
#   Car             $1,000   $800 Maintenance due in 56 days  free $200   on track
#   Insurance         $400   $400 Premium due in 3 days       free   $0   on track
#   Gas                $40   $150 a period rate rule          free   $0
#   Rent              $100   $2,000 Rent Bill due in 40 days  free   $0
#   Cushion           $500   savings goal, no rules           free $500
#   Coffee            $150   $100 a period, funded a fortnight ago — its period has CLOSED
#
# THE INVARIANT IS `available + Σ holdings == income − expenses`, and a hand move cannot change it:
# the money stays inside the user's own purpose ledger. Every total is pinned against the LITERAL
# $3,000 deposit below rather than against a sum of the app's own parts.
RSpec.shared_context "with categories to reallocate between" do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  # The pot, for income to land in (`Category#income_must_land_in_an_account`). No figure below is
  # read off it.
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST, and nothing here reads it: income
  # lands in a category and `Category#income_must_land_in_an_account` says that category may
  # only point at the user's MAIN account, so a user with no account cannot be paid at all. It
  # is setup for the physical side of a fixture whose every assertion is on the purpose side.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup
  let(:dentist) { category("Dentist") }
  let(:car) { category("Car") }

  before do
    sign_in user, scope: :user
    deposit(3_000)
    dated_rule(holder("Dentist", priority: 1), "Dental Work", 300, due_in: 3)
    dated_rule(holder("Car", priority: 2, funded: 1_000), "Maintenance", 800, due_in: 56)
    dated_rule(holder("Insurance", priority: 3, funded: 400), "Premium", 400, due_in: 3)
    rate_rule(holder("Gas", priority: 4, funded: 40), 150)
    dated_rule(holder("Rent", priority: 5, funded: 100), "Rent Bill", 2_000, due_in: 40)
    savings("Cushion", funded: 500)
    closed_category("Coffee", rate: 100, funded: 150)
  end

  # A SYNCHRONISATION POINT, NOT AN EXPECTATION: a hook doing two round trips has to wait for the
  # first to land, and Capybara's predicates are what block until it does.
  def await(content)
    return if page.has_content?(content)

    raise "expected the page to show #{content.inspect} before the next step"
  end

  # The one route a foreign source can reach `create` by, since the screen never renders a radio for
  # one: the real form, with one field's value hand-edited. Clicked first, because changing a radio's
  # value does not check it.
  def submit_with_source(target)
    find_by_id("from-#{car.id}").click
    page.execute_script("document.getElementById('from-#{car.id}').value = '#{target.id}'")
    click_on "Move the money"
  end

  # The same hand-edit for the DESTINATION select, which carries no option for a stranger's category
  # any more than the radios carry one: the option is appended and selected before the form is
  # submitted, so `create` is reached the only way it can be.
  def submit_with_destination(target)
    page.execute_script(
      "const s = document.getElementById('move-to-category');" \
      "s.insertAdjacentHTML('beforeend', \"<option value='#{target.id}'>x</option>\");" \
      "s.value = '#{target.id}';"
    )
    click_on "Move the money"
  end

  # The distribution's write path, called directly: these files are about what a hand move does to a
  # distribution, not about the distribution screen, which has its own specs.
  def distribute
    AllocationCommitter.new(AllocationCalculator.new(user: user, today: Date.current)).call
  end

  def category(name) = user.categories.find_by!(name: name)

  # A FRESHLY BUILT calculator every time: HoldingCalculator memoises and is stale-after-write by
  # construction, so one held across a move answers from before it.
  def holding_of(name) = Category.find(category(name).id).holding_calculator.balance

  # MONEY WITH NO JOB YET — the root, and what "your buffer" names on these screens. A fresh ledger
  # every time, for the same reason.
  def available = CategoryLedger.new(user.categories.expenses.to_a, user: user).available

  # THE §2 PARTITION, compared against the literal deposit the fixture planted and never against a
  # sum of its own parts.
  def purpose_total
    categories = user.categories.expenses.to_a
    ledger = CategoryLedger.new(categories, user: user)

    ledger.available + categories.sum(0.to_d) { |c| ledger.holding_of(c) }
  end

  def holder(name, priority:, funded: 0, **attrs)
    category = create(:category, :expense, :funded, user: user, name: name, priority: priority, **attrs)
    fund(category, funded)
    category
  end

  def savings(name, funded:)
    holder(name, priority: 6, funded: funded, target_amount: 5_000)
  end

  def fund(category, amount, on: Date.current)
    return if amount.zero?

    create(:allocation, to_category: category, amount: amount, date: on)
  end

  # A one-time dated rule with a payable item, so BudgetCalculator has a real fulfilment signal and
  # `interval_months: nil` keeps :behind out of the picture — a cycle it has no interval to spread
  # over cannot put the category behind schedule, which keeps every figure here exact.
  def dated_rule(category, item_name, amount, due_in:)
    create(
      :budget,
      pool: nil,
      category: category,
      item: create(:item, category: category, name: item_name),
      amount: amount,
      interval_months: nil,
      anchor_date: Date.current + due_in
    )
  end

  def rate_rule(category, amount)
    create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
  end

  # A category funded a fortnight ago — one biweekly boundary back — so its rate period has closed
  # and HoldingCalculator#period_closed? is true. The whole of its leftover is what the next
  # distribution sweeps back, which is the shape `net_of_sweep:` exists for.
  def closed_category(name, rate:, funded:)
    category = holder(name, priority: 7)
    rate_rule(category, rate)
    fund(category, funded, on: Date.current - 14)
    category
  end

  def deposit(amount)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end
end
