# frozen_string_literal: true

require "rails_helper"

# Task 7: moving money between two envelopes when life happens — one movement, from, to, amount,
# inside one account.
#
# THE INVARIANT IS `Σ pools == your bank balance`, and a reallocation cannot change it: the money
# stays in the account, so the bank holds exactly what it held. Every total below is pinned
# against the LITERAL deposit the fixture planted ($3,000) rather than against a sum of the app's
# own parts — `Pool#total` IS that sum, so summing the parts against it is `x == x` and passes
# after any write whatsoever.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and matches the
# sidebar. Every figure below is scoped to the row that owns it.
#
# The fixture, all figures exact, and every envelope but Coffee funded today so nothing sweeps:
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
RSpec.describe "Pool Movements Move", type: :system do
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

  # THE STATE BEFORE ANY AMOUNT IS TYPED. Without it every assertion below would also pass on a
  # screen that had already moved the money, or that had quietly dropped half its rows.
  describe "the screen, before an amount is entered", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id) }

    # SAME-ACCOUNT ONLY (spec §5), asserted in both directions on one screen: Checking's own
    # envelopes are offered, and an envelope in a second account is not — which is not the same as
    # a screen that simply failed to render its list.
    it "offers this account's pools and no others" do
      expect(page).to have_css("[data-source='Car']")
      expect(page).to have_css("[data-source='Checking']")
      expect(page).to have_css("[data-source='Cushion']")
      expect(page).to have_no_css("[data-source='Holiday']")
      expect(page).to have_no_css("[data-source='Dentist']")
    end

    # Nothing to state yet, and both halves matter: the sources are on screen, so the absence of
    # the two sentences is a decision rather than an empty page.
    it "states no damage and no gain until there is a move to describe" do
      expect(page).to have_no_css("#reallocation-gain")
      expect(page).to have_no_css("[data-damage]")
      expect(page).to have_css("[data-source]", minimum: 5)
    end
  end

  describe "the damage statement", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id, amount: 300) }

    # SPEC §5'S OWN LINE, rebuilt: `Car $1,340 → $1,122 — Maintenance slips to $494/$800`. The
    # per-period figure is a real recomputation of PoolCalculator#required — $100 of shortfall
    # over the 5 period boundaries between today and the due date — and NOT $300 divided by
    # anything, which is what makes $20.00 rather than $60.00 the right answer.
    it "names the rule that slips and what the envelope will ask for" do
      within("[data-damage='Car']") do
        expect(page).to have_content("$1,000.00 → $700.00")
        expect(page).to have_content("its Maintenance rule slips to $700.00 of $800.00")
        expect(page).to have_content("asks $20.00 a period instead of $0.00")
      end
    end

    # THE OPPOSITE DIRECTION, on the same screen. A savings goal with no rules holds nothing back,
    # so the move takes only free money: nothing slips and nothing asks for more, and the line
    # says so by not saying it (spec §5: state the consequence only when there is one).
    it "says nothing about a rule or a period when neither moves" do
      within("[data-damage='Cushion']") do
        expect(page).to have_content("$500.00 → $200.00")
        expect(page).to have_no_content("slips to")
        expect(page).to have_no_content("a period instead of")
      end
    end

    # The red case, in the state the app already has for it rather than a new one. Taking $300 of
    # Insurance's $400 leaves $300 owed on a bill with no period boundary left before it is due.
    it "says when the move leaves the source unable to make its date" do
      within("[data-damage='Insurance']") do
        expect(page).to have_content("its Premium rule slips to $100.00 of $400.00")
        expect(page).to have_content("becomes won't make it")
      end
      expect(page).to have_css("[data-damage='Insurance'].text-status-danger")
      expect(page).to have_css("[data-damage='Cushion'].text-gray-500")
    end

    # WHY `net_of_sweep:` IS ON BOTH RECOMPUTATIONS. Coffee's rate period closed a fortnight ago,
    # so the next distribution takes its whole leftover back and tops the envelope up to its full
    # rate either way — taking $100 out of it costs NOTHING per period. Read through a plain
    # calculator the row would say "asks $50.00 a period instead of $0.00", a cost the very next
    # distribution erases. The rule's allocation still slips, and that is true and worth saying.
    it "says nothing about a period when the leftover was going to be swept anyway" do
      visit new_pool_movement_path(to_pool_id: dentist.id, amount: 100)

      within("[data-source='Coffee']") { expect(page).to have_content("$150.00 left · last period") }
      within("[data-damage='Coffee']") do
        expect(page).to have_content("$150.00 → $50.00")
        expect(page).to have_content("its Per period rule slips to $50.00 of $100.00")
        expect(page).to have_no_content("a period instead of")
      end
    end

    # WHAT THE COST BUYS, and the destination's own row vocabulary on both sides of the move.
    it "states what the destination gains" do
      within("#reallocation-gain") do
        expect(page).to have_content("Dentist $0.00 → $300.00")
        expect(page).to have_content("won't make it")
        expect(page).to have_content("becomes $300.00 · on track")
      end
    end
  end

  # "SHOWN BUT DISABLED, WITH THE REASON" (amendment D). Both directions on one screen, and the
  # enabled half is what makes the disabled half mean something: a row that had simply vanished
  # would satisfy every negative assertion here.
  describe "a source that cannot make the move", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id, amount: 300) }

    it "disables it and says how little is in it" do
      expect(page).to have_css("[data-source='Gas'] input[type=radio][disabled]")
      within("[data-source-reason='Gas']") do
        expect(page).to have_content("Can't make this move — only $40.00 in it")
      end
    end

    # The other reason, which is a different sentence because it sends the user somewhere else:
    # the envelope is thin because a dated bill is already holding what is in it.
    it "names the bill that is holding the money" do
      within("[data-source-reason='Rent']") do
        expect(page).to have_content("only $100.00 in it")
        expect(page).to have_content("its Rent Bill rule is due")
        expect(page).to have_content("is holding $100.00")
      end
    end

    # The paired positive: a source that CAN make the move is enabled, states what it holds and
    # what of that is free, and carries no refusal.
    it "leaves an affordable source enabled and says what it holds" do
      expect(page).to have_css("[data-source='Car'] input[type=radio]:not([disabled])")
      within("[data-source-reason='Car']") do
        expect(page).to have_content("$1,000.00 in it · $200.00 of it free")
        expect(page).to have_no_content("Can't make this move")
      end
    end
  end

  describe "moving the money", :aggregate_failures do
    before do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      click_on "Move the money"
      await("Moved $300.00")
    end

    it "lands on Home and says what it did, from the ledger" do
      expect(page).to have_content("Moved $300.00 from Car to Dentist. Car $700.00 · Dentist $300.00")
      expect(page).to have_css("h1", text: "Home")
    end

    # ONE ROW, AND A `transfer` — the column default, which is exactly what keeps it out of
    # `PoolMovement.distributed`.
    it "writes one transfer and nothing a distribution owns" do
      moved = PoolMovement.where(from_pool: car, to_pool: dentist)
      expect(moved.count).to eq(1)
      expect(moved.first).to be_kind_transfer
      expect(moved.first.amount).to eq(300)
      expect(PoolMovement.distributed.count).to eq(0)
    end

    # The two balances move by exactly the amount, in opposite directions, and the bank does not
    # move at all — pinned against the fixture's own $3,000 deposit.
    it "moves the money between the two pools and creates none" do
      expect(balance_of("Car")).to eq(700)
      expect(balance_of("Dentist")).to eq(300)
      expect(balance_of("Checking")).to eq(810)
      expect(bank_balance).to eq(3_000)
    end

    # THE PREVIEW WAS TRUE. The left side was computed before the write through
    # PoolCalculator's `pending:`; the right side is read out of the database afterwards. Two
    # independent routes to the same figures, which is the whole point of building the damage
    # statement out of the same readers the ledger will produce.
    it "leaves the envelopes exactly where the screen said it would" do
      expect(balance_of("Car")).to eq(700)
      within("[data-pool-name='Car']") { expect(page).to have_content("$700.00") }
      within("[data-pool-name='Dentist']") { expect(page).to have_content("$300.00") }
    end
  end

  # AMENDMENT A, IN BOTH DIRECTIONS. A redistribution replaces the period's own rows and must
  # leave a hand-made move alone: a user who moves $50 between envelopes and then redistributes
  # still has their $50 move.
  #
  # THE MOVE HAS TO TOUCH THE ACCOUNT or this example proves nothing, and that was measured rather
  # than reasoned: AllocationCommitter#previous_distribution matches on `from_pool: account OR
  # to_pool: account`, so an envelope-to-envelope row is spared by the ACCOUNT filter whatever kind
  # it carries. Written Car → Dentist, this passed with `kind: :allocation` forced on — the row was
  # never a candidate for deletion in the first place. Rent → the Checking buffer sits squarely
  # inside the date window AND on the account, so `distributed` is the only thing sparing it, which
  # is the fact amendment A is about.
  describe "surviving a redistribution", :aggregate_failures do
    let(:distributed_before) { PoolMovement.distributed.pluck(:id) }
    let(:transfer) { PoolMovement.where(from_pool: pool("Rent"), to_pool: checking).sole }

    before do
      distribute
      distributed_before
      visit new_pool_movement_path(to_pool_id: checking.id, from_pool_id: pool("Rent").id, amount: 300)
      click_on "Move the money"
      await("Moved $300.00")
      transfer
      distribute
    end

    it "replaces the distribution's own rows" do
      expect(distributed_before).not_to be_empty
      expect(PoolMovement.distributed.pluck(:id)).not_to include(*distributed_before)
      expect(PoolMovement.distributed).to be_any
    end

    it "leaves the reallocation untouched" do
      expect(PoolMovement.where(id: transfer.id)).to exist
      expect(transfer.reload).to be_kind_transfer
      expect(bank_balance).to eq(3_000)
    end
  end

  # NOTHING IS WRITTEN AND THE SCREEN SAYS WHY. Three refusals, each reaching the server by a
  # different route, and each paired against the move that does succeed above.
  describe "refusals", :aggregate_failures do
    it "refuses a blank amount and writes nothing" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      expect { click_on "Move the money" }.not_to(change(PoolMovement, :count))
      expect(page).to have_css("#reallocation-errors", text: "Nothing moved")
      expect(page).to have_content("Amount can't be blank")
    end

    # The browser's own refusal of a zero, before anything is submitted: a zero move is not an
    # event (amendment E) and the box says so rather than the server having to.
    it "refuses a zero amount in the box" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      fill_in "How much", with: "0"
      expect { click_on "Move the money" }.not_to(change(PoolMovement, :count))
      expect(page).to have_css("input#move-amount:invalid")
    end

    # SPEC §5 AT THE WRITE. The source list never offers Holiday, so this reaches `create` the only
    # way it can — a hand-edited field — and is refused by PoolMovement's own #crosses_accounts?.
    it "refuses a source in another account" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      expect { submit_with_source(pool("Holiday")) }.not_to(change(PoolMovement, :count))
      expect(page).to have_content("must be in the same account")
      expect(balance_of("Dentist")).to eq(0)
    end
  end

  # AMENDMENT B: a stranger's pool can be neither end. Both ends, both verbs, and each paired with
  # the request that does work.
  describe "another user's pools", :aggregate_failures do
    let(:stranger_pool) { create(:pool, :budget_pool, name: "Someone Else's") }

    it "does not open on one as the destination" do
      visit new_pool_movement_path(to_pool_id: stranger_pool.id)
      expect(page).to have_content("We couldn't find that envelope")
      expect(page).to have_no_content("Where it comes from")
      visit new_pool_movement_path(to_pool_id: dentist.id)
      expect(page).to have_content("Where it comes from")
    end

    it "does not move money out of one" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      expect { submit_with_source(stranger_pool) }.not_to(change(PoolMovement, :count))
      expect(page).to have_content("We couldn't find that envelope")
      expect(balance_of("Dentist")).to eq(0)
    end
  end

  describe "the form itself", :aggregate_failures do
    # THE LINK SHAPE TASK 8 WILL USE, arriving with both ends and the amount already chosen: the
    # boxes come back holding them and the move is one click away.
    it "arrives prefilled from a link" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(page).to have_field("How much", with: "300.00")
      expect(find_by_id("from-#{car.id}")).to be_checked
    end

    # MEASURED IN A BROWSER, NOT REASONED ABOUT. `shared/_date_selector` — the month scrubber in
    # the sidebar chrome — re-emits every scalar query parameter as a hidden field in each of its
    # two forms, so a field whose id is the bare param name shares that id with two hidden inputs.
    # `label for=` and `getElementById` both reach the hidden one first: before the fix,
    # `document.getElementById("amount")` on this page returned a hidden input carrying "300"
    # rather than the box the user types in. Every example above passed either way, because
    # Capybara filters invisible elements and landed on the right one by luck.
    it "does not share a DOM id with the page chrome" do
      visit new_pool_movement_path(to_pool_id: dentist.id, amount: 300)

      expect(duplicate_dom_ids).to include("amount", "to_pool_id")
      expect(duplicate_dom_ids).not_to include("move-amount", "move-to-pool")
      expect(page).to have_css("input#move-amount[type=number]", count: 1)
      expect(page).to have_field("How much", with: "300.00")
    end

    it "recomputes when the destination and amount are typed in" do
      visit new_pool_movement_path
      select "Dentist", from: "Envelope"
      fill_in "How much", with: "300"
      click_on "Update figures"
      within("[data-damage='Car']") { expect(page).to have_content("$1,000.00 → $700.00") }
    end

    # HTML'S IMPLICIT SUBMISSION. Enter in a number field activates the FIRST submit button in
    # tree order — so with the move button first, the most natural keystroke there is in a numeric
    # box would move the money on a screen whose entire purpose is stating the cost first. The
    # distribution screen shipped exactly that defect and it wrote a $2,900 split on a keypress.
    # Both halves on one keystroke: nothing was written, and the recompute that should have
    # happened did.
    it "recomputes rather than moving money when Enter is pressed in the amount box" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      fill_in "How much", with: "300"
      find_field("How much").send_keys(:enter)

      expect(page).to have_css("[data-damage='Car']")
      expect(PoolMovement.where(from_pool: car, to_pool: dentist)).not_to exist
      expect(balance_of("Dentist")).to eq(0)
    end
  end

  private

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

  # Task 6's write path, called directly: this file is about what a reallocation does to a
  # distribution, not about the distribution screen, which has its own spec.
  def distribute
    proposal = AllocationCalculator.new(user: user, account: checking, today: Date.current)
    AllocationCommitter.new(proposal).call
  end

  # Every id that appears more than once in the rendered document, sidebar chrome included.
  def duplicate_dom_ids
    page.evaluate_script(<<~JS)
      (() => {
        const seen = new Set(), duplicated = new Set();
        document.querySelectorAll("[id]").forEach((element) => {
          if (seen.has(element.id)) { duplicated.add(element.id); }
          seen.add(element.id);
        });
        return Array.from(duplicated);
      })()
    JS
  end

  def pool(name) = user.pools.find_by!(name: name)

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
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)
  end

  # An envelope funded a fortnight ago — one biweekly boundary back — so its rate period has closed
  # and PoolCalculator#period_closed? is true. The whole of its leftover is what the next
  # distribution sweeps back, which is the shape `net_of_sweep:` exists for.
  def closed_envelope(name, rate:, funded:)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: 7)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
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
