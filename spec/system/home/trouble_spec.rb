# frozen_string_literal: true

require "rails_helper"

# HOME'S TROUBLE STRIP — rendered ONLY when something real needs a human (answers-first spec §5,
# computed-claims §4). This file is `spec/system/home/attention_spec.rb`'s successor, converted onto
# claims by computed-claims Task 3.
#
# ** SILENCE IS THE GOOD STATE. ** There is no permanent "Nothing needs you" box, so the absence of
# the strip IS the good news and every trigger below is asserted in BOTH directions.
#
# ── THE TRIGGERS, AND WHAT HAPPENED TO EACH ONE (Task 3):
#
#   :overdraft  — a non-main bank account below zero. UNCHANGED: it is a fact about the PHYSICAL
#                 ledger, which this plan does not touch. Both examples carried whole, copy verbatim.
#   :shortfall  — NEW (§4). `free < 0` is the signal, and the strip states the figure, walks the
#                 uncovered claims in REVERSE PRIORITY (the give-way order) and names the per-day pace
#                 that lands the period at zero. ** ITS HEADLINE IS THE HERO'S ARM TABLE (fix round 1
#                 — HIGH-1): three arms, each gated on the predicate that establishes its cause, and
#                 the give-way list on only one of them. See "the three arms" below.
#   :over       — a rule spent past what it had (§3.1). It REPLACES `overdrawn`, which measured a
#                 category's HOLDING going negative; there are no holdings.
#   :overdue    — an occurrence past its date that nobody has settled (§3.2). It REPLACES `overdue`
#                 and `won't make it` together. ** IT FIRES ON THE DATE ALONE (fix round 1 — MED-1). **
#                 It was gated on `built_up < target` as well, which silenced the ordinary case: the
#                 catch-up formula fills an unpaid fund in ONE period, so the WHOLE fund is the usual
#                 shape of a bill past its date, not the exception. The fund state splits the
#                 SENTENCE ("the fund is short $X" / "it's all there"), and both are pinned.
#   :structural — UNCHANGED. `Budget.steady_need` against declared income reads the rules and the
#                 calendar and nothing else. All six examples carried.
#
# ── DELETED WITH THE DISTRIBUTION (computed-claims §§5-6). Each asserted a fact about money that had
# been MOVED, and nothing moves:
#
#   * "asks the user to distribute when this period's money has not been handed out", "falls silent
#     once this period has been distributed", "asks nothing of a user whose rules ask for nothing" —
#     the :undistributed trigger. There is nothing to hand out; the state it was really about (rules
#     asking for more than there is) is the :shortfall arm, which asks for something a user can
#     actually do.
#   * "shows a category that can't be funded in time" / "leaves a bill the schedule can still reach
#     out of the strip" — `won't make it` compared a category's holding against a catch-up rate. See
#     :overdue above for the pair that replaces them.
#   * "shows a behind category with the rule it is behind on" — `behind` was "holds less than the
#     rules have asked for so far", which is the gap between an ask and an allocation.
#   * the "overdrawn category whose period has ended" pair — ` · last period` named money awaiting a
#     sweep. A rate claim resets at the boundary by definition (§3.1); there is no leftover.
#   * the whole "a category that went behind because a rule was changed" group (five examples) —
#     `DistributionClock` compares a rule's `updated_at` against the moment this period's split was
#     written, and there is no split.
#   * "fits a problem row and its fix button inside a 375px viewport" — CONVERTED, not deleted: the
#     fix buttons are gone (a fix was a purpose-side MOVE), so the narrow pin measures the widest
#     thing the strip still holds, which is the shortfall arm's uncovered list.
#
# ** `spec/system/home/fixes_spec.rb` (638 lines) WAS DELETED WHOLE WITH THE FIX APPARATUS, AND THIS
# FILE IS WHERE THAT IS RECORDED (fix round 1 — LOW-3). ** It was the only file naming those examples
# and it left no successor saying so, which is the one way a deletion in this codebase goes unnoticed.
# Every example in it asserted an ALLOCATION — "Take $300.00 from Rent", the candidate list, the
# amount it proposed, the /allocations/new form it opened — and §5 leaves the purpose side with no
# movements at all: there is nothing to take money FROM, because no claim is money sitting anywhere.
# The behaviour that replaced them all is one sentence and one door, pinned here as "sends the user to
# the rules rather than offering to move money". `ReallocationPresenter` and `/allocations/new` are
# untouched and still serve the reallocation screen until Task 4.
#
# EVERY COPY ASSERTION IN THIS FILE GOES THROUGH A DATA HOOK — `[data-trouble]`,
# `[data-problem-category]`, `[data-problem-state]`, `[data-problem-detail]`,
# `[data-overdrawn-account]`, `[data-shortfall]`, `[data-shortfall-amount]`,
# `[data-shortfall-pace]`, `[data-uncovered-claim]`, `[data-sacrifice-link]`.
RSpec.describe "Home Trouble", type: :system do
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

  def strip = find("[data-trouble]")

  def problem_row(name) = find("[data-problem-category='#{name}']")

  def uncovered(name) = find("[data-uncovered-claim='#{name}']")

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

  # `type:` DEFAULTS TO `usage`, THE COLUMN'S OWN DEFAULT (rules-own-the-budget spec §6 step 3) — so
  # every fixture written before rules had a type keeps the order it had, and an example that names
  # one is saying so on purpose.
  def envelope(name, amount, priority: 1, type: :usage)
    holder(name, priority: priority).tap do |category|
      create(:budget, :per_period_rate, category: category, amount: amount, rule_type: type)
    end
  end

  # ** AN ALLOWANCE THAT KEEPS WHAT IT DOESN'T SPEND (two-shapes §12). ** `#envelope`'s columns plus
  # the one that says the boundary leaves the money alone, born as the current period opened — so the
  # walk visits exactly one period and the built-up is one period's rate before any spending.
  def a_fund(name, amount, priority: 1, type: :usage)
    holder(name, priority: priority).tap do |category|
      create(
        :budget,
        :keeps_unspent,
        category: category,
        amount: amount,
        rule_type: type,
        created_at: Time.current.beginning_of_day
      )
    end
  end

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  def spend(category, amount, on: Date.current)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A bill that accrues toward a date (§3.2). Item-less, so its fulfilment lane is the whole category
  # — which is what lets `spend` above settle it.
  def accumulating(name, amount:, due:, priority: 1, every: 1)
    holder(name, priority: priority).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: every, anchor_date: due)
    end
  end

  # A ONE-TIME BILL ON AN ITEM — the shape whose occurrence never rolls. `created_at` IS PLANTED,
  # for the ruling of 2026-09-03: a rule accrues from the LATER of its category's funding date and
  # its OWN birth, so a rule the factory writes at real-now walks only today's period and a receipt
  # dated ten days ago would move nothing at all. Returns the ITEM, because the caller settles the
  # rule by spending on its lane.
  def one_off_bill(name, amount:, due:)
    create(:item, category: holder(name), name: "Water").tap do |item|
      create(
        :budget,
        :one_time,
        category: item.category,
        item: item,
        amount: amount,
        anchor_date: due,
        created_at: 2.months.ago
      )
    end
  end

  # A ONE-TIME BILL ON AN ITEM — the shape whose occurrence never rolls. `created_at` IS PLANTED, for
  # the ruling of 2026-09-03: a rule accrues from the LATER of its category's funding date and its
  # OWN birth, so a rule the factory writes at real-now walks only today's period and a receipt dated
  # ten days ago would move nothing at all. Returns the ITEM, because the caller settles the rule by
  # spending on its lane.
  def one_off_bill(name, amount:, due:)
    create(:item, category: holder(name), name: "Water").tap do |item|
      create(
        :budget,
        :one_time,
        category: item.category,
        item: item,
        amount: amount,
        anchor_date: due,
        created_at: 2.months.ago
      )
    end
  end

  # A MOVE ON THE PHYSICAL LEDGER. `move_out` puts CHECKING in the red; `move_in` is its mirror and is
  # the only way to put a NON-main account below zero while every claim stays healthy.
  #
  # `:opened` — the account has said what it holds (account-openings §3). It is load-bearing for the
  # transfer line: `#money_parked_elsewhere?` totals `#other_accounts`, which EXCLUDES an account
  # still being asked what is in it, so an unanswered Ally would hold the money and the strip would
  # offer no remedy for it.
  def move_out(amount)
    ally = create(:pool, :account, :opened, user: user, name: "Ally")
    create(:account_movement, from_pool: checking, to_pool: ally, amount: amount, date: Date.current, kind: :transfer)
  end

  def move_in(amount)
    ally = create(:pool, :account, :opened, user: user, name: "Ally")
    create(:account_movement, from_pool: ally, to_pool: checking, amount: amount, date: Date.current, kind: :transfer)
  end

  # ── THE STRIP'S ABSENCE, WHICH IS THE DESIGN (answers-first §5) ────────────────────────────────

  # A permanent placeholder is exactly what §5 rules out. PLANTED: a $400 rate rule and $400 of
  # income — `claim = max(0, 400 − 0)` = $400, `free = min(400, 400 − 400)` = $0.00, which is not
  # negative, so nothing at all is true.
  it "renders nothing at all when nothing is wrong", :aggregate_failures do
    deposit(400)
    envelope("Groceries", 400)

    visit root_path

    expect(page).to have_css("[data-money]")
    expect(page).to have_no_css("[data-trouble]")
    expect(page).to have_no_content("Nothing needs you")
    expect(page).to have_no_content("needs you")
  end

  # ── TRIGGER: FREE BELOW ZERO (computed-claims §4) ──────────────────────────────────────────────

  # THE FIXTURE THE SHORTFALL EXAMPLES SHARE: three rate rules in priority order 1-2-3, claiming
  # $1,000, $400 and $200 with nothing spent — Σ claims $1,600.00 (§3.1).
  def three_rules
    envelope("Rent", 1_000, priority: 1)
    envelope("Groceries", 400, priority: 2)
    envelope("Fun", 200, priority: 3)
  end

  # ** THE GIVE-WAY WALK, PINNED WITH THREE RULES AND A SHORTFALL THAT SPLITS ONE CLAIM. **
  #
  # PLANTED, and every figure re-derived from §3's formulas:
  #   Rent      priority 1, $1,000 a period, nothing spent → claim `max(0, 1,000 − 0)` = $1,000.00
  #   Groceries priority 2,   $400 a period, nothing spent → claim   $400.00
  #   Fun       priority 3,   $200 a period, nothing spent → claim   $200.00
  #   Σ claims = $1,600.00; the pot is the $1,340 deposit.
  #   free = 1,340 − 1,600 = **−$260.00**; shortfall $260.00.
  #
  # THE WALK RUNS IN REVERSE PRIORITY — priority is the GIVE-WAY order (§4), so the category that
  # would have been funded LAST goes without FIRST. Fun's whole $200 is uncovered; $60 of the $260 is
  # left, so GROCERIES IS SPLIT — short $60 of its $400 — and RENT, first in priority, is not reached
  # at all. The split is the reason this is a walk rather than a filter.
  #
  # THE PACE: the period is biweekly anchored today, so today is day 1 of 14 and `days_left` is 13.
  # `260 ÷ 13` = **$20.00** a day.
  it "states the shortfall, who gives way, and the pace that lands the period at zero", :aggregate_failures do
    deposit(1_340)
    three_rules

    visit root_path

    expect(page).to have_css("[data-free]", text: "-$260.00")
    expect(find("[data-shortfall-amount]")).to have_content("short $260.00")
    expect(find("[data-shortfall-pace]")).to have_content("Spending $20.00 a day less")
    expect(uncovered("Fun")).to have_content("nothing covers its $200.00")
    expect(uncovered("Groceries")).to have_content("short $60.00 of $400.00")
    expect(page).to have_no_css("[data-uncovered-claim='Rent']")
    # THE ORDER IS THE WALK'S, and asserting the list's text catches a strip that found the right two
    # claims by luck and printed them highest-priority-first.
    expect(find("[data-uncovered]").text).to match(/Fun.*Groceries/m)
  end

  # ** THE TYPE DECIDES BEFORE PRIORITY DOES (rules-own-the-budget spec §3), AND THE STRIP IS WHERE A
  # USER MEETS IT. ** The same three rules and the same $260 shortfall as above, with the priorities
  # INVERTED against the types: the choice rule is on priority 1 — the most protected category under
  # the old reverse-priority walk — and the bill on priority 3. So the two orders disagree about
  # every row, and this fixture answered `Rent short $260.00` before the type was read: the app
  # naming the rent as the thing to go without.
  #
  # PLANTED, re-derived from §3.1: Fun $200, Groceries $400, Rent $1,000, nothing spent, Σ claims
  # $1,600.00 against a $1,340 deposit → `free` −$260.00 and the shortfall $260.00. CHOICE goes
  # whole ($200), USAGE is split at the remaining **$60.00**, and the BILL is never reached.
  it "gives way by type before priority — choice whole, usage split, a bill never", :aggregate_failures do
    deposit(1_340)
    envelope("Fun", 200, priority: 1, type: :choice)
    envelope("Groceries", 400, priority: 2, type: :usage)
    envelope("Rent", 1_000, priority: 3, type: :bill)

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $260.00")
    expect(uncovered("Fun")).to have_content("nothing covers its $200.00")
    expect(uncovered("Groceries")).to have_content("short $60.00 of $400.00")
    expect(page).to have_no_css("[data-uncovered-claim='Rent']")
    expect(find("[data-uncovered]").text).to match(/Fun.*Groceries/m)
  end

  # ** WITHIN ONE TYPE, PRIORITY STILL DECIDES AND STILL DECIDES BACKWARDS. ** Two CHOICE rules, so
  # the type term ties and the category term does all the work: the one that would have been funded
  # LAST goes without FIRST.
  #
  # PLANTED: Dining priority 1 and Hobbies priority 3, $300 a period each, against a $200 deposit.
  # Σ claims $600.00 → `free` −$400.00, shortfall $400.00. Hobbies gives its whole $300 and
  # Dining is short the remaining **$100.00**.
  it "gives way in reverse priority order inside one type", :aggregate_failures do
    deposit(200)
    envelope("Dining", 300, priority: 1, type: :choice)
    envelope("Hobbies", 300, priority: 3, type: :choice)

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $400.00")
    expect(uncovered("Hobbies")).to have_content("nothing covers its $300.00")
    expect(uncovered("Dining")).to have_content("short $100.00 of $300.00")
    expect(find("[data-uncovered]").text).to match(/Hobbies.*Dining/m)
  end

  # THE REMEDY IS A RULE, NOT A MOVE (§4). There is nothing to take money FROM — no claim is money
  # sitting anywhere — so the arm carries a door to the Budget page and no fix button at all.
  it "sends the user to the rules rather than offering to move money", :aggregate_failures do
    deposit(100)
    envelope("Rent", 1_000)

    visit root_path

    expect(find("[data-shortfall]")).to have_link("Change a rule on the Budget page", href: budget_page_path)
    expect(strip).to have_no_content(/take .* from/i)
    expect(strip).to have_no_content(/available/i)
  end

  # THE OTHER DIRECTION: the same three rules against enough money. `1,800 − 1,600` = $200 free, which
  # is not negative, so there is no shortfall arm and no strip at all.
  it "says nothing about a shortfall when the claims fit", :aggregate_failures do
    deposit(1_800)
    three_rules

    visit root_path

    expect(page).to have_css("[data-free]", text: "$200.00")
    expect(page).to have_no_css("[data-shortfall]")
    expect(page).to have_no_css("[data-trouble]")
  end

  # ── THE TWO ARMS OF `free < 0`, WHICH ARE THE HERO'S (two-shapes spec §2) ──────────────────────
  #
  # ** IT WAS THREE ARMS AND THE `min` IS WHAT MADE IT SO. ** `free = min(pot, total_money − Σ
  # claims)` went below zero for two unrelated reasons — the claims outrun the money, or the money is
  # in another account — so the strip needed a "Checking is short" headline for the second and a
  # predicate that ESTABLISHED which. `free = pot − Σ claims` has one cause per sign: the rules claim
  # more than checking holds. What splits the headline now is whether anything is claimed AT ALL, and
  # what money elsewhere buys is a REMEDY rather than an explanation.
  #
  # Each example asserts the wrong sentence ABSENT as well as the right one present — the failure
  # these were written for was a strip printing a true-sounding sentence, not a missing one.

  # ** ARM 1: SOMETHING IS CLAIMED, AND THE GIVE-WAY WALK BELONGS TO IT. ** The three-rule fixture
  # above, asked for its headline: $1,600 claimed against $1,340 in checking.
  it "heads the shortfall with the figure the rules claim past checking", :aggregate_failures do
    deposit(1_340)
    three_rules

    visit root_path

    expect(find("[data-shortfall-headline]")).to have_content("Your rules claim $260.00 more than checking holds")
    expect(page).to have_no_css("[data-shortfall-elsewhere]")
    expect(page).to have_css("[data-uncovered]")
  end

  # ** MONEY IN ANOTHER ACCOUNT IS THE REMEDY, NOT THE CAUSE (§2). ** $1,000 of income, $1,200 walked
  # over to Ally, NOT ONE RULE: the pot is −$200 and nothing is claimed, so the headline is the pure
  # overspend's and the second line is what to do about it. The strip used to say "Checking is short"
  # with a sentence about money "sitting outside checking", which was an account of the arithmetic
  # rather than an instruction — and the arm it lived on was the cap's.
  it "offers the transfer when another account holds money", :aggregate_failures do
    deposit(1_000)
    move_out(1_200)

    visit root_path

    expect(find("[data-shortfall-headline]")).to have_content("You have spent past what you had")
    expect(find("[data-shortfall-amount]")).to have_content("short $200.00")
    expect(find("[data-shortfall-elsewhere]"))
      .to have_content("$1,200.00 of your money is sitting outside checking — move some in from your other accounts")
    expect(page).to have_no_css("[data-uncovered]")
    # THE PACE SURVIVES BOTH ARMS: spending less lands the figure at zero whichever way it got there.
    expect(page).to have_css("[data-shortfall-pace]")
  end

  # ** ARM 2: THE PURE OVERSPEND, WITH NOWHERE TO MOVE MONEY IN FROM. ** `hero_spec`'s "is honest
  # when spending has drained the root", asked of the strip. PLANTED: $100 spent on a funded category
  # carrying NO rule and no income at all — Σ claims is $0.00 and the pot is −$100.00, so `free` is
  # −$100.00. "Your rules claim $X more" would name something that does not exist, and there is
  # nothing for a give-way walk to list.
  it "says the account was spent past zero when no rule claims a penny", :aggregate_failures do
    spend(holder("Groceries"), 100)

    visit root_path

    expect(page).to have_css("[data-free]", text: "-$100.00")
    expect(find("[data-shortfall-headline]")).to have_content("You have spent past what you had")
    expect(find("[data-shortfall-amount]")).to have_content("short $100.00")
    expect(strip).to have_no_content("Your rules claim")
    expect(page).to have_no_css("[data-uncovered]")
    # One account, and the money was SPENT rather than moved: there is nowhere to send this user.
    expect(page).to have_no_css("[data-shortfall-elsewhere]")
  end

  # ** THE WALK RUNS WHEREVER CHECKING IS SHORT, WHATEVER ANOTHER ACCOUNT HOLDS (§2). ** It was gated
  # on `#claims_outrun_the_money?`, because the capped `free` could go below zero with every claim
  # covered by money outside checking — and the walk ran there anyway, naming Groceries as uncovered
  # with the account holding its money printed two inches below. There is one cause per sign now, so
  # the gate is `#short?` and the walk is honest about CHECKING.
  #
  # PLANTED: $800 of income, $1,000 walked to Ally, one $500-a-period rule with nothing spent (claim
  # **$500.00**). The pot is −$200.00 and Σ claims $500.00, so `free` is **−$700.00**: Groceries'
  # whole $500 is uncovered and the remaining **$200.00** is past every claim there is. The transfer
  # line is what tells the user the money exists.
  it "walks the claims and offers the transfer when the money is in another account", :aggregate_failures do
    deposit(800)
    move_out(1_000)
    envelope("Groceries", 500)

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $700.00")
    expect(find("[data-shortfall-elsewhere]")).to have_content("$1,000.00 of your money is sitting outside")
    expect(uncovered("Groceries")).to have_content("nothing covers its $500.00")
    expect(find("[data-uncovered-remainder]")).to have_content("$200.00 past everything the rules claim")
  end

  # ** THE PART OF THE SHORTFALL NO CLAIM ACCOUNTS FOR (fix round 1 — LOW-1). ** The walk runs out of
  # claims and the list then sums to LESS than the headline, with nothing naming the difference.
  #
  # PLANTED: $400 spent on a funded category with no rule and no income, beside a $500-a-period rule
  # with nothing spent. Σ claims $500.00 against a pot of −$400.00 → `free = −400 − 500` =
  # **−$900.00**. Groceries' whole $500 goes; `900 − 500` =
  # **$400.00** is past every claim there is.
  it "names the part of the shortfall that is past every claim", :aggregate_failures do
    spend(holder("Coffee", priority: 3), 400)
    envelope("Groceries", 500, priority: 2)

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $900.00")
    expect(uncovered("Groceries")).to have_content("nothing covers its $500.00")
    expect(find("[data-uncovered-remainder]")).to have_content("$400.00 past everything the rules claim")
  end

  # THE OTHER DIRECTION: a shortfall the claims absorb leaves no remainder, and a line about $0.00
  # past everything would report nothing. The three-rule fixture's $260 is split inside the list.
  it "says nothing about a remainder when the claims absorb the shortfall", :aggregate_failures do
    deposit(1_340)
    three_rules

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $260.00")
    expect(page).to have_css("[data-uncovered]")
    expect(page).to have_no_css("[data-uncovered-remainder]")
  end

  # NO DECLARED PERIOD, NO PACE — the same refusal `#period_range` makes about the same reader, since
  # there is no "rest of the period" to spread a shortfall over. The figure and the list survive,
  # because both are true whatever calendar the user keeps.
  #
  # PLANTED: one $1,000-a-period rule against $100 of income. `free = 100 − 1,000` = −$900.00, so
  # the shortfall is $900 and the single claim is SPLIT by it — short $900 of its $1,000, not wholly
  # uncovered, which is the walk's `min(claim, remaining)` said on one row.
  it "states the shortfall without a pace before a period is declared", :aggregate_failures do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    deposit(100)
    envelope("Rent", 1_000)

    visit root_path

    expect(find("[data-shortfall-amount]")).to have_content("short $900.00")
    expect(uncovered("Rent")).to have_content("short $900.00 of $1,000.00")
    expect(page).to have_no_css("[data-shortfall-pace]")
  end

  # ── TRIGGER: A RULE SPENT PAST WHAT IT HAD (§3.1) ──────────────────────────────────────────────

  # PLANTED: a $150-a-period rate rule with $180 spent. §3.1 — the claim is `max(0, 150 − 180)` =
  # $0.00 and `#over?` reads the figure BEFORE that clamp, so the row says the excess: `180 − 150` =
  # **$30.00**. The $1,000 deposit keeps `free` positive so this is the ONLY thing on the strip.
  it "names a rule that has been spent past what it had", :aggregate_failures do
    deposit(1_000)
    spend(envelope("Dining Out", 150), 180)

    visit root_path

    expect(strip).to have_content("1 thing needs you")
    expect(problem_row("Dining Out").find("[data-problem-state]")).to have_content("over by $30.00")
    expect(problem_row("Dining Out").find("[data-problem-detail]"))
      .to have_content("$180.00 spent of $150.00")
    expect(problem_row("Dining Out")).to have_content("comes straight out of what is free")
  end

  # ** AND A FUND'S OVERSPEND IS MEASURED AGAINST WHAT IT HAD, NOT AGAINST A PERIOD (two-shapes §12;
  # fix round — MED). ** The detail was `<spent> spent of <accrued>`, written out in the view, and
  # `accrued` is THIS PERIOD's accrual: a fund holding hundreds and spent past them read
  # "$900.00 spent of $60.00" beside a header saying "over by $34.00" — two figures that cannot both
  # be about one rule. `HomeHelper#claim_over_detail` is the one spelling now and it names the
  # built-up, which is the figure the spending actually outran.
  #
  # PLANTED SO EVERY FIGURE IS DERIVABLE, on the file's biweekly grid anchored today: a $60 fund born
  # on the period's own open walks ONE period, so it holds $60.00 before the receipt; $94 spent
  # leaves `60 − 94` = **−$34.00** before the clamp, which is `over by $34.00` and a claim of zero.
  # `$94.00 spent, $0.00 built up` is the pair — the built-up AFTER the spending, which is what the
  # row's own figure says everywhere else on this screen.
  it "measures a fund's overspend against what it had built up", :aggregate_failures do
    deposit(1_000)
    spend(a_fund("Pet Care", 60), 94)

    visit root_path

    expect(problem_row("Pet Care").find("[data-problem-state]")).to have_content("over by $34.00")
    expect(problem_row("Pet Care").find("[data-problem-detail]"))
      .to have_content("$94.00 spent, $0.00 built up")
    expect(problem_row("Pet Care").find("[data-problem-detail]")).to have_no_content("spent of")
  end

  # THE OTHER DIRECTION, on a category that spent to the penny: exactly the rate is the tidiest
  # outcome there is, and reading it as trouble would be the same lie as `-$0.00`. `#over?` is a
  # strict comparison for exactly this reason.
  it "leaves a rule spent exactly to its rate out of the strip", :aggregate_failures do
    deposit(1_000)
    spend(envelope("Dining Out", 150), 150)

    visit root_path

    expect(page).to have_no_css("[data-problem-category='Dining Out']")
    expect(page).to have_no_css("[data-trouble]")
  end

  # THE STRIP AND THE SECTION RENDER THE SAME RULE INCHES APART, and an over rule is in both by
  # construction. One string, one helper (`HomeHelper#claim_trouble_label`), so the screen cannot
  # disagree with itself about the same $30.
  it "reads the same in the strip as in the period section", :aggregate_failures do
    deposit(1_000)
    spend(envelope("Dining Out", 150), 180)

    visit root_path

    expect(problem_row("Dining Out").find("[data-problem-state]")).to have_content("over by $30.00")
    # ** THE SECTION SAYS THE SAME $30 IN THE FIGURE RATHER THAN IN A CLAUSE (two-shapes §3). ** The
    # block row's clause is the DAY — a rate rule's is `resets <boundary>` — and the excess is the
    # strip's own sentence, printed once. What the row must still say is the pair the excess is the
    # difference of, in red, which is the half of this example that is about the two panels agreeing.
    expect(find("[data-category-block='Dining Out'] [data-rule-figure]")).to have_content("$180.00 of $150.00")
  end

  # ── TRIGGER: A DUE DATE PASSED WITH THE FUND SHORT (§3.2) ──────────────────────────────────────

  # ** OVERDUE IS THE DATE (fix round 1 — MED-1), AND THE FUND STATE IS THE INSTRUCTION. **
  #
  # PLANTED: a $1,200 monthly bill anchored ten days ago, with $500 of the category's spending inside
  # this period. §3.2's catch-up formula — `planned = (target − built_up) ÷ periods_left`, and
  # `periods_left` floors at 1 for a date already past — accrues the whole $1,200 in this period; the
  # walk then settles the period's spending, so `raw = 1,200 − 500` and `built_up` is **$700.00**.
  # $500 is less than one cycle, so `cycles_paid_by` stays at 0 and the occurrence does not roll: the
  # date is still ten days ago and the fund is `1,200 − 700` = **$500.00** short of it.
  it "names a bill whose date has passed while its fund is short", :aggregate_failures do
    deposit(2_000)
    due = Date.current - 10.days
    spend(accumulating("Utilities", amount: 1_200, due: due), 500)

    visit root_path

    expect(problem_row("Utilities").find("[data-problem-state]"))
      .to have_content("overdue · was #{due.strftime("%b %-d")}")
    # ** "the fund is short" IS "$500.00 short" NOW (fix round 1 — MED-6). ** "fund" named the retired
    # shape — a rule whose unspent money carried over — and this row is about a DATED rule, which may
    # be a bill somebody must pay or a target they chose to save toward. The sentence is about the
    # MONEY either way, so it names the shortfall and the instruction and lets the row's own label
    # say what the rule is.
    expect(problem_row("Utilities").find("[data-problem-detail]"))
      .to have_content("$700.00 built up of $1,200.00 — $500.00 short — this needs paying")
    expect(problem_row("Utilities")).to have_no_content("the fund is short")
  end

  # ** THE HALF THAT USED TO BE SILENT, AND IT IS THE ORDINARY CASE. ** The same bill with nothing
  # spent: the catch-up formula floors `periods_left` at 1 for a date already past, so the fund fills
  # to the full $1,200 in ONE period. Under the old `built_up < target` gate that user — who had
  # saved every penny and simply not paid the bill — got SILENCE, and their row printed `next due`
  # over a date ten days gone. The bill still has to be paid; what changes is the sentence.
  # ** AND THE `else` IT USED TO SHARE WITH AN UNCAPPED FUND IS GONE (two-shapes §7). ** The arm
  # carried a second branch for a rule that named no figure — unreachable even then, since only a
  # DATED rule can be overdue and a dated rule's target is its own amount — and the shape that could
  # have reached it is retired. This example and the one above it are the whole of what the gate
  # renders.
  it "names a bill whose date has passed even with the fund whole", :aggregate_failures do
    deposit(2_000)
    due = Date.current - 10.days
    accumulating("Utilities", amount: 1_200, due: due)

    visit root_path

    expect(problem_row("Utilities").find("[data-problem-state]"))
      .to have_content("overdue · was #{due.strftime("%b %-d")}")
    expect(problem_row("Utilities").find("[data-problem-detail]"))
      .to have_content("$1,200.00 built up of $1,200.00 — it's all there — pay it and it starts again")
    expect(problem_row("Utilities")).to have_no_content("short")
    expect(problem_row("Utilities")).to have_no_content("fund")
  end

  # ** A PAID ONE-OFF IS SILENT, AND IT USED TO BE THE LOUDEST ROW ON THE SCREEN (two-shapes Task
  # 3's carry (a)). ** A ONE-TIME rule's occurrence never rolls — there is no interval to roll onto,
  # which is exactly what makes the two examples above safe on a REPEATING bill — so a one-off paid
  # on the 18th and due on the 24th read `overdue · was <date>` from the 25th onward, for ever, with
  # "this needs paying" beside it. `ClaimCalculator#settled?` is the fulfilment and the strip fires
  # on the date AND it.
  #
  # BOTH DIRECTIONS ON ONE FIXTURE, because a strip that had simply stopped firing would pass the
  # second half alone: the same rule is named before the payment and absent after it.
  it "drops a one-off from the strip once it has been paid", :aggregate_failures do
    deposit(2_000)
    due = Date.current - 10.days
    water = one_off_bill("Utilities", amount: 600, due: due)

    visit root_path
    expect(problem_row("Utilities").find("[data-problem-state]")).to have_content("overdue · was")

    create(:entry, item: water, amount: 600, date: due)
    visit root_path

    expect(page).to have_no_css("[data-problem-category='Utilities']")
    expect(page).to have_no_content("this needs paying")
  end

  # THE OTHER DIRECTION, WHICH IS NOW THE DATE'S: a bill still ahead of its date is a fund SAVING,
  # which is what the catch-up formula is for and is not trouble. Silence is the good state.
  it "leaves a bill whose date is still ahead out of the strip", :aggregate_failures do
    deposit(2_000)
    accumulating("Utilities", amount: 1_200, due: Date.current + 10.days)

    visit root_path

    expect(page).to have_no_css("[data-problem-category='Utilities']")
    expect(page).to have_no_css("[data-trouble]")
    expect(find("[data-category-block='Utilities'] [data-rule-figure]"))
      .to have_content("$1,200.00 of $1,200.00")
  end

  # ── TRIGGER: A PHYSICAL OVERDRAFT (answers-first §5) ───────────────────────────────────────────

  # CARRIED WHOLE, copy verbatim. It is a NON-MAIN account: main's overdraft IS the red "In Checking"
  # figure with its own sentence (§2), and printing the same debt twice with two different sentences
  # about what counts it is worse than printing it once.
  it "names a non-main account that has gone below zero", :aggregate_failures do
    deposit(1_000)
    move_in(200)

    visit root_path

    expect(strip).to have_css("[data-overdrawn-account='Ally']", text: "Ally is overdrawn $200.00")
    expect(strip).to have_content("none of the figures above count it")
    # The pot is fine — $1,000 of income plus the $200 that walked in — so the hero's figure must not
    # have turned red as well.
    expect(page).to have_no_css("[data-in-checking].text-status-danger")
  end

  # THE OTHER DIRECTION, and it is the one that keeps the debt from being reported twice: main is
  # overdrawn, the hero says so in red, and the strip does not repeat it.
  it "leaves main's own overdraft to the hero", :aggregate_failures do
    deposit(500)
    move_out(900)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]", text: "already spent past zero")
    expect(page).to have_no_css("[data-overdrawn-account='Checking']")
  end

  # ── TRIGGER: THE BUDGET DOES NOT FIT THE INCOME (§9's permanent button) ────────────────────────

  # The href is asserted, not just the label: a button that says the budget does not fit and goes
  # nowhere is the state this replaced, and it looked identical.
  it "shows the structural warning only when rules exceed typical income", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path

    expect(strip).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
    expect(strip).to have_css("[data-sacrifice-link]")
  end

  it "hides the structural warning when the budget fits", :aggregate_failures do
    deposit(1_000)
    envelope("Groceries", 400)

    visit root_path

    expect(page).to have_no_link("Your budget doesn't fit your income")
    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # THE BUTTON AND THE ROUTE ARE THE SAME CONDITION READ TWICE. Home shows it on
  # `structurally_underwater?` and /sacrifice refuses on the same test, so a button that rendered
  # where the route refuses would open a redirect straight back. Followed rather than merely asserted,
  # because only following it can tell the two apart.
  it "opens the sacrifice view when followed", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path
    click_link "Your budget doesn't fit your income"

    expect(page).to have_current_path(sacrifice_path)
    expect(page).to have_content("$600.00 underwater every period")
  end

  # THE HERO AND THE BUTTON ANSWER DIFFERENT QUESTIONS, which is why §9 asks for the button to be
  # permanent. This period's cash is fine — `5,000 − 3,000` leaves $2,000 free — and the budget still
  # does not fit the income ($3,000 a period against $2,400).
  it "keeps the button up on a period whose cash is comfortable", :aggregate_failures do
    envelope("Rent", 3_000)
    deposit(5_000)

    visit root_path

    expect(page).to have_css("[data-free]", text: "$2,000.00")
    expect(strip).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
  end

  it "shows no structural warning before an income is declared" do
    user.update!(typical_income: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # INCOME WITHOUT A CADENCE IS REACHABLE — the declaration form offers "Not set" for the period —
  # and `Budget.steady_need` still answers there, against a period the user has not agreed to. The
  # gate is both halves, and this is the half that only fails when one of them is dropped.
  it "shows no structural warning before a period is declared" do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # ── THE SCREEN THAT MUST NOT FALL OVER ────────────────────────────────────────────────────────

  # CARRIED, AND THE GUARD MOVED. A rule whose amount is negative took out the ROOT ROUTE rather than
  # one screen, through the waterfall's `remaining.clamp(0.to_d, needed)`. There is no waterfall; what
  # holds the line now is §3.2's PER-PERIOD CLAMP AT ZERO, and this example is what says so.
  #
  # PLANTED: a Vacation category whose only rule carries −$150, beside a $400 rate rule, against $100
  # of income. §3.1's clamp takes that rule's claim to **$0.00** rather than letting a negative claim
  # ADD to what is free — Σ claims is the $400 rate rule alone, `free = 100 − 400` = **−$300.00**.
  # A missing clamp reads −$150 here and the figure would be −$150.00.
  #
  # THE CATEGORY NAMED $2,400 UNTIL THE SHAPES MOVED ONTO THE RULE and the arithmetic above quoted it
  # as a `gap`. It was already dead weight before the column was dropped, so the figure is gone from
  # the fixture and from the working.
  it "renders when a rule's amount is negative", :aggregate_failures do
    vacation = holder("Vacation", priority: 2)
    create(:budget, :per_period_rate, category: vacation, amount: 150)
    vacation.budgets.first.update_column(:amount, -150) # rubocop:disable Rails/SkipsModelValidations
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_css("[data-free]", text: "-$300.00")
    expect(page).to have_css("[data-shortfall-amount]", text: "short $300.00")
    expect(page).to have_no_css("[data-uncovered-claim='Vacation']")
  end

  # ── THE NARROW BREAKPOINT ──────────────────────────────────────────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT via CDP — `money_spec.rb`'s mechanism (`hero_spec.rb` until the
  # money column renamed it), copied deliberately: Chrome
  # refuses a headless window narrower than 500px, so `resize_to(375, …)` is really a 500px test.
  # No `evaluate_script` anywhere in the example, for that file's measured reason: Selenium's own
  # geometry says what this example is about without running a line of JS.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # THE WIDEST THING THE STRIP HOLDS IS AN UNCOVERED ROW — a category name, its rule and a
    # two-figure sentence on one line — now that the fix buttons are gone. Four-figure amounts, so the
    # row is as wide as this design can make it.
    it "fits the shortfall arm and its uncovered list inside a 375px viewport", :aggregate_failures do
      deposit(1_000)
      envelope("Rent", 1_500, priority: 1)
      envelope("Groceries", 1_200, priority: 2)

      visit root_path

      expect(uncovered("Groceries")).to have_content("nothing covers its $1,200.00")

      panel = page.find("[data-trouble]").native.rect
      claim = uncovered("Groceries").native.rect

      expect(panel.x + panel.width).to be <= 375
      expect(claim.x + claim.width).to be <= panel.x + panel.width
    end
  end
end
