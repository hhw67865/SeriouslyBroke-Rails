# frozen_string_literal: true

require "rails_helper"

# HOME'S ATTENTION BAND, on the purpose ledger (two-ledger spec §2).
#
# ONE KIND OF PROBLEM WHERE THERE WERE THREE. The pool era listed an overdrawn ACCOUNT and a pool
# with no account beside the envelopes whose own status needed attention. Both extra terms are
# deleted with the shapes they described, and the examples that pinned them are named where they
# stood.
RSpec.describe "Home Attention", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `checking` FIRST, so it is the account the `:account` trait nominates as main — every category
  # the helpers below mint would otherwise pull the factory's own account into being and claim the
  # nomination.
  before do
    checking
    sign_in user, scope: :user
  end

  # A CATEGORY THAT HOLDS MONEY, filled at a rate every period.
  def envelope(name, amount, priority: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: amount)
    end
  end

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

  # Income lands in main and raises available at the same instant (§2).
  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # AVAILABLE → A CATEGORY. It moves nothing physical, which is why no example below can produce an
  # overdrawn ACCOUNT with one.
  def fund(category, amount, on: Time.zone.now)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  def spend(category, amount, on: Date.current)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A dated bill the user actually pays: an item is the only fulfilment signal BudgetCalculator
  # accepts, and therefore the only way a rule can be overdue rather than settled by its own date.
  def payable(name, amount:, due:, priority: 1)
    holder(name, priority: priority).tap do |category|
      item = create(:item, category: category, name: "#{name} Bill")
      create(
        :budget,
        category: category,
        item: item,
        amount: amount,
        interval_months: 1,
        anchor_date: due
      )
    end
  end

  # A MOVE ON THE PHYSICAL LEDGER, out of Checking and into a second account. It is the only way to
  # put one account in the red while every category and available stay healthy — see the example
  # that uses it.
  def move_out(amount)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:account_movement, from_pool: checking, to_pool: ally, amount: amount, date: Date.current, kind: :transfer)
  end

  def attention_section = find("section[aria-labelledby='attention-heading']")

  def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

  it "lists a category that can't be funded in time", :aggregate_failures do
    dentist = holder("Dentist")
    create(:budget, :one_time, category: dentist, amount: 300, anchor_date: Date.current + 3.days)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Dentist")
      expect(page).to have_content("won't make it")
      expect(page).to have_content("1 thing needs you")
      expect(page).to have_no_content("Nothing needs you")
    end
  end

  it "says nothing needs you when every category is quiet", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", 400), 400)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing needs you")
      expect(page).to have_no_content("Groceries")
      expect(page).to have_no_content("overdrawn")
    end
  end

  it "shows no waterfall when there is no gap to explain", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_content("Nothing needs you")
    expect(page).to have_no_content("Where your money goes")
    expect(page).to have_no_content("ran out here")
  end

  # Seen on the screen: `won't make it · Aug 18` sat under "You're covered this period" with the
  # waterfall hidden, because the waterfall only rendered when short. HoldingStatus describes the
  # category NOW; the waterfall describes the plan. Showing the warning while suppressing its own
  # resolution is the worst combination of the two.
  it "shows where the money goes when a category needs you on a covered period", :aggregate_failures do
    dentist = holder("Dentist")
    create(:budget, :one_time, category: dentist, amount: 300, anchor_date: Date.current + 3.days)
    deposit(1_000)

    visit root_path

    # WAS `have_content("You're covered")` (answers-first Task 1). The standing band's headline is
    # deleted — the hero card renders in every state (spec §2) — so the covered period is now the
    # figure it produces: $1,000 in, $300 spoken for, $700 free. The example is about the WATERFALL
    # rendering beside a flagged category, and that half is untouched.
    expect(page).to have_css("[data-free-to-spend]", text: "$700.00")
    expect(waterfall_section).to have_content("$300.00 of $300.00")
    # Nothing ran out, so the cutoff must stay away.
    expect(waterfall_section).to have_no_content("ran out here")
  end

  # A category that asked for nothing rendered "$0.00 of $0.00", and below the cutoff that reads as
  # money denied rather than money not wanted.
  it "leaves a category that asks for nothing out of the waterfall", :aggregate_failures do
    settled = envelope("Rent", 300)
    deposit(500)
    fund(settled, 300)
    envelope("Groceries", 400, priority: 2)

    visit root_path

    expect(waterfall_section).to have_content("Groceries")
    expect(waterfall_section).to have_no_content("Rent")
    expect(waterfall_section).to have_no_content("$0.00 of $0.00")
  end

  # "Something needs you" is NOT the same question as "is there a plan to show": the zero-need
  # reject can empty the row list outright, and the band would render its heading over nothing —
  # which on a money screen reads as data that failed to load.
  #
  # THE FIXTURE MOVED WITH THE MODEL. It used to be an overdrawn ACCOUNT, which had no waterfall row
  # by construction; an overdrawn account is not a problem row any more, so the shape that reaches
  # this branch is an OVERDUE bill whose category already holds every penny of it — red, and asking
  # for nothing.
  it "shows no plan when the problem has no waterfall row", :aggregate_failures do
    utilities = payable("Utilities", amount: 120, due: Date.current - 10.days)
    deposit(120)
    fund(utilities, 120)

    visit root_path

    expect(page).to have_content("1 thing needs you")
    expect(page).to have_content("overdue")
    expect(page).to have_no_content("Where your money goes")
  end

  # ── AN OVERDRAWN ACCOUNT IS NOT A PROBLEM ROW (Task 6), and this example is the old
  # "gives an overdrawn account a voice even when every envelope is quiet" INVERTED rather than
  # deleted, because the debt still has to be visible.
  #
  # The fix beside a problem row is an ALLOCATION, and an allocation moves nothing physical (§2) —
  # so offering one against a bank overdraft would propose a mistake to fix a problem it cannot
  # reach, which is the same ruling that keeps a fix off an overdue bill whose category already
  # holds the money. The standing band names the account and the figure in red; the attention band
  # says nothing needs you, because on the purpose ledger nothing does.
  #
  # THE FIXTURE NEEDS TWO ACCOUNTS and that is a fact about the invariant rather than a convenience:
  # `pot + Σ accounts == available + Σ holdings`, so a single-account user whose pot is $400 down is
  # $400 down on the purpose side too. A movement between two accounts is the only way to put one
  # account in the red while every category and available stay healthy.
  it "names an overdrawn account without counting it as something that needs you", :aggregate_failures do
    deposit(500)
    move_out(900)
    fund(envelope("Groceries", 400), 400)

    visit root_path

    # WAS the standing band's strip, "Checking is overdrawn $400.00 — … none of the figures above
    # count it" (answers-first Task 1). Checking is MAIN, and the hero's own figure IS the pot, so
    # that last clause became false the moment the card started printing it: the overdraft is now
    # the red "In Checking" line with its own sentence (spec §2). The strip survives verbatim for a
    # NON-main account, which `spec/system/home/hero_spec.rb` covers — what this example is about is
    # the attention band staying quiet, and that is unchanged.
    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]", text: "already spent past zero")
    within(attention_section) do
      expect(page).to have_content("Nothing needs you")
      expect(page).to have_no_content("overdrawn")
    end
  end

  # ── DELETED (Task 6), on top of the five the pool tightening already took:
  #
  #   * "gives an overdrawn account a voice even when every envelope is quiet" — inverted above.
  #   * "draws no cutoff when the user has more than one account". The `accounts.one?` gate was
  #     there because each account drained its own pot, so with several there was no single moment
  #     the money ran out. One root, one moment: the line is drawn whatever the user banks with, and
  #     `home_presenter_spec`'s "#cutoff draws the line for a user with several accounts" is the
  #     positive that replaced it.

  # The state that is short with nothing flagged: every rate category reads `left_to_spend`, so
  # nothing needs attention while the period is genuinely $300 down. "Nothing needs you" here would
  # be the exact lie this band exists to prevent.
  it "never says nothing needs you while the money runs out", :aggregate_failures do
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing is flagged, but you're still short")
      expect(page).to have_no_content("Nothing needs you")
      expect(page).to have_content("Where your money goes")
    end
  end

  # The cutoff branch where the money ran out inside the LAST row, so nothing sits below the line
  # and it has to render at the end of the list rather than not at all.
  it "shows the waterfall with a cutoff when short", :aggregate_failures do
    ["Rent", "Groceries"].each_with_index do |name, i|
      envelope(name, 500, priority: i + 1)
    end
    deposit(700)

    visit root_path

    expect(page).to have_content("Where your money goes")
    expect(page).to have_content("ran out here")
  end

  # A savings goal whose rule carries a NEGATIVE amount — written past Budget's validation
  # deliberately, exactly as allocation_calculator_spec's twin does, because the shape being
  # defended against is a row that reached the table some other way and that is precisely what a
  # validation cannot promise.
  def broken_goal(name, amount)
    holder(name, priority: 2, target_amount: 2_400).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: amount.abs)
      category.budgets.first.update_column(:amount, amount) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # A RULE WHOSE AMOUNT IS NEGATIVE, and Home is the ROOT ROUTE — this took out the whole app rather
  # than one screen.
  #
  # HoldingCalculator#goal_required returns `[rate, remaining].min`, so a goal carrying a negative
  # rule asks for a negative figure, and the waterfall's `remaining.clamp(0.to_d, needed)` raises
  # ArgumentError on it — `BigDecimal("100").clamp(0, -150)` raises.
  #
  # BOTH SIDES OF THE GUARD, and they are independent: the raw reader is still negative (that is the
  # input), while the SCREEN renders and #remaining_plan counts the bad rule as zero rather than
  # subtracting $150 from what the user owes — a wrong total is worse than a crash on a money
  # screen, and only the floor prevents both.
  it "renders when a rule's amount is negative", :aggregate_failures do
    vacation = broken_goal("Vacation", -150)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    # WAS `have_content("$300.00 short this period")` (answers-first Task 1): the same $300 gap,
    # said in the user's words by the card that replaced the standing band — $100 in checking
    # against a $400 plan.
    expect(page).to have_css("[data-free-to-spend]", text: "-$300.00")
    expect(waterfall_section).to have_content("$100.00 of $400.00")
    expect(Category.find(vacation.id).holding_calculator.required).to eq(-150)
    expect(HomePresenter.new(user: user).remaining_plan).to eq(400)
  end

  # THE TWO BANDS ANSWER DIFFERENT QUESTIONS AND SAY SO.
  #
  # The problem row offers HoldingStatus#funding_gap — the whole cumulative hole, read from the live
  # holding. The waterfall row prints #required — THIS period's share of it, post-sweep. Both are
  # right (see HomePresenter#fix_amount_for) and neither figure changes; what was missing was
  # anything on the screen saying they are measured over different spans.
  #
  # Car Insurance is $1,200 every six months due six biweekly boundaries out, so this period's share
  # is a stable $171.43 whatever day the suite runs — while the steady-schedule gap depends on how
  # many boundaries fall inside a six-month cycle on that calendar, so it is READ rather than pinned
  # to a second literal. Rent takes the root first, which is what keeps Car's row short and therefore
  # keeps its button: a category the waterfall funds in full is deliberately offered no move at all.
  describe "the whole gap above, this period's share below" do
    before do
      envelope("Rent", 1_000, priority: 0)
      car = holder("Car Insurance", priority: 1)
      create(
        :budget,
        category: car,
        amount: 1_200,
        interval_months: 6,
        anchor_date: Date.current + 84
      )
      deposit(1_100)
      visit root_path
    end

    def gap = user.categories.find_by!(name: "Car Insurance").status.funding_gap.round(2)

    # AVAILABLE IS THE SOURCE THE BUTTON NAMES, where the pool era named "Checking buffer": the
    # buffer is the purpose ledger's root now (§7.1 re-anchored), it is not a category, and
    # `ReallocationPresenter::Root#name` is the one place it is spelled.
    it "prints both figures for one category, inches apart", :aggregate_failures do
      expect(gap).to be > 171.43 # the whole hole really is bigger than this period's share
      within(find("[data-problem-category='Car Insurance']")) do
        expect(page).to have_link("Take #{number_to_currency(gap)} from Available")
      end
      within(waterfall_section) { expect(page).to have_content("$100.00 of $171.43") }
    end

    # The bridge. A BAND LABEL, not a seventh clause on every row — said once, above the rows.
    it "labels the band so the two are not read as two answers to one question", :aggregate_failures do
      within(waterfall_section) do
        expect(page).to have_content("This period's share — what the next distribution puts in, not the whole gap.")
      end
      expect(waterfall_section.text.scan("This period's share").size).to eq(1)
      expect(find("[data-problem-category='Car Insurance']")).to have_no_content("This period's share")
    end
  end

  # WHICH PERIOD THE FIGURE BELONGS TO, IN THE ATTENTION BAND — the suffix this band was the one
  # caller in the app to omit.
  #
  # `#pool_problem_label` passed `changed_after_distributing:` and NOT `period_closed:`, so ONE Home
  # render printed `overdrawn $80.00 · last period` in the categories band and `overdrawn $80.00` in
  # the attention band a few inches above it. Both bands are asserted here, on one visit, because
  # that is where the disagreement was visible.
  #
  # THE PAIR IS THE POINT. Two rate categories with the SAME rule, the SAME spending and therefore
  # the same `overdrawn $80.00`, differing only in which side of a period boundary their money
  # arrived on. A lone closed-period row would pass against a suffix printed unconditionally.
  #
  # :overdrawn rather than :behind because `HoldingCalculator#period_closed?` is false for a category
  # with any anchored rule, and :overdrawn is the one attention state guarded on the holding alone.
  describe "an overdrawn category whose period has ended" do
    before do
      deposit(2_000)
      swept = envelope("Swept", 400, priority: 1)
      live = envelope("Live", 400, priority: 2)
      # Two periods back on a biweekly cadence anchored today, so the rate rule's own period —
      # measured from `last_funded_on`, which is this allocation — closed before today.
      fund(swept, 100, on: Date.current - 21.days)
      fund(live, 100, on: Date.current)
      spend(swept, 180)
      spend(live, 180)
      visit root_path
    end

    it "marks the closed period on the problem row, and only on that one", :aggregate_failures do
      expect(find("[data-problem-category='Swept']")).to have_content("overdrawn $80.00 · last period")
      within(find("[data-problem-category='Live']")) do
        expect(page).to have_content("overdrawn $80.00")
        expect(page).to have_no_content("last period")
      end
    end

    # THE TWO BANDS, ONE SCREEN, ONE VISIT. This is the assertion the defect would have failed: the
    # same category, rendered inches apart, read `overdrawn $80.00 · last period` below and
    # `overdrawn $80.00` above. Compared to a literal on both sides rather than to each other, so a
    # label that lost its amount fails here rather than agreeing with itself about nothing.
    it "reads the same in the attention band as in the categories band", :aggregate_failures do
      expect(find("[data-problem-category='Swept']")).to have_content("overdrawn $80.00 · last period")
      expect(find("[data-holding-name='Swept']")).to have_content("overdrawn $80.00 · last period")
      expect(find("[data-problem-category='Live']")).to have_no_content("last period")
      expect(find("[data-holding-name='Live']")).to have_no_content("last period")
    end
  end

  # The cutoff sits where the money ran out, and a category funded $200 of $500 did receive money: it
  # belongs ABOVE the line, with only the ones that got nothing below it.
  it "draws the cutoff beneath the last category that got any money", :aggregate_failures do
    { "Rent" => 500, "Groceries" => 500, "Dentist" => 500 }.each_with_index do |(name, amount), i|
      envelope(name, amount, priority: i + 1)
    end
    deposit(700)

    visit root_path

    expect(waterfall_section.text).to match(/Rent.*Groceries.*ran out here.*Dentist/m)
    expect(waterfall_section).to have_content("$200.00 of $500.00")
    expect(waterfall_section).to have_content("$0.00 of $500.00")
    expect(waterfall_section).to have_content("$800.00 unfunded")
  end
end
