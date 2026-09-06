# frozen_string_literal: true

require "rails_helper"

# HOME, ON THE PHYSICAL LEDGER AND THE CLAIMS COMPUTED OVER IT (computed-claims spec §§2-4). This
# file was pool-shaped once and allocation-shaped until Task 3; every figure below now comes from
# §3's formulas, re-derived by hand with the working written beside it.
#
# ── DELETED WITH THE READERS THEY ASSERTED (Task 3). Every one of them measured money that had been
# MOVED into a category, and nothing moves any more (§5). The old readers are still ALIVE for the
# Distribute screen until Task 4; HOME simply stopped asking them:
#
#   * `#available` (7 examples) — `AllocationCalculator#available`, the distribution's post-sweep
#     root. `free` is `min(pot, total_money − Σ claims)` now, which needs no root at all.
#   * `#remaining_plan` (4) — Σ over the waterfall's rows of what each category still asked for. A
#     claim is not an ask against a balance; it IS the figure.
#   * `#waterfall` and its three sibling describes (9) — the fill, the ties, the red root, the
#     asks-for-nothing row. There is no fill.
#   * `#plan_outruns_the_money?` (4) — CONVERTED to `#claims_outrun_the_money?` below, at its own
#     fixtures where they survive the change of readers.
#   * `#anything_set_aside_or_spoken_for?` (3) — CONVERTED to `#anything_claimed?`. Its two nouns
#     were a HOLDING and a distribution's remaining ask.
#   * `#status_for` (3) and `#dated_rules_for` (4) — `HoldingStatus` and `BudgetCalculator` per row.
#     What a row says is now one `ClaimCalculator` per rule, off the page's one `ClaimLedger`.
#   * `#attention_categories` (2) — the strip's population is `#troubles`, which is asserted whole.
#   * `#fix_for` (7) — the whole fix apparatus. A fix was an ALLOCATION.
#
# ── NEW, BECAUSE THE MODEL IS (§4): `#shortfall`, `#uncovered_claims` (the give-way walk) and
# `#per_day_pace`.
#
# ── ** `#period_rows` AND `PeriodRow` ARE DELETED WITH THE BLOCKS (two-shapes spec §3), AND EVERY
# ONE OF THEIR EXAMPLES IS ACCOUNTED FOR BELOW. ** A row per CATEGORY could not say what §3 asks
# for — a category's own rules ranked by TYPE, since almost every category has several — so the
# section is a block per category with a row per rule, ordered by the one walk this screen already
# had (`#give_way_order`, grouped back):
#
#   * the six figure examples ("counts the spending inside this period and no other", the dated
#     rule, the goal's target, the goal's bar, the two-rule category, the unbudgeted partition) are
#     CARRIED at their own figures, reading `#category_blocks.sole.rows` where they read
#     `#period_rows.sole.lines`. Not one number moved: a `ClaimLine` is the same object.
#   * "sorts trouble first and keeps priority order behind it" is DELETED at its own site, with the
#     second ordering it asserted. The reason is written there.
#   * "keeps a rule-less holder only while it has spending" MOVED to `#unbudgeted_rows`, which is
#     the reader that answers for that row now.
#
# ── NEW WITH §3: `#runway` (the ticks, their days and their two states), `#pace_line` (both signs
# of `free`), `#category_blocks` (the order, the header figures and the tint) and the row vocabulary
# `ClaimLine` carries for `HomeHelper` — `#name`, `#stripe_type`, `#short?`, `#bar_state`.
RSpec.describe HomePresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  # `checking` is the account this whole file treats as primary, and several examples mint a SECOND
  # account before ever touching it — the auto-main factory trait claims whichever account it sees
  # first for a user with none named. Forcing it here rather than disciplining every example's
  # creation order.
  before { user.update!(default_account: checking) }

  # A CATEGORY THAT HOLDS MONEY (spec §3): an expense category with a `funded_since`. The date is a
  # LITERAL and not `1.year.ago`, because this file's clock is fixed at Feb 2026 and a wall-clock
  # funding date would slide past it in a real year (CLAUDE.md's third flake cause).
  def holder(name, priority:, funded_since: Date.new(2025, 1, 1))
    create(:category, :expense, user: user, name: name, priority: priority, funded_since: funded_since)
  end

  # ** A GOAL IS A DATED RULE, NOT A KIND OF CATEGORY (two-shapes spec §2 row 5). ** The category it
  # sits on is an ordinary holder; the figure to reach and the day to reach it by are both the rule's
  # own columns, and `ClaimCalculator` reads nothing else.
  def savings_goal(name, priority:) = holder(name, priority: priority)

  # ** THE RULE A GOAL IS: `amount` IS the target and `anchor_date` is the day (§2). ** It was a
  # zero-amount rule that carried its money over toward a separate figure — "no rate" spelled as a
  # zero — and there is no such shape: a goal's per-period share is `remaining ÷ periods until the
  # date`, so the horizon replaces the rate.
  #
  # `due:` DEFAULTS TO ONE PERIOD OUT, which makes the walk's arithmetic the simplest it can be: with
  # one boundary left the catch-up share is the whole remaining target, so a goal born today holds
  # exactly its target. The birthday is planted for the reason `#bill` states: a rule younger than
  # `today` walks no periods and holds nothing.
  def goal_rule(category, target:, due: today, created_at: Time.zone.local(2025, 1, 1))
    create(
      :budget,
      category: category,
      amount: target,
      basis: :monthly,
      interval_months: nil,
      anchor_date: due,
      created_at: created_at
    )
  end

  # A flat per-period rule: the catch-all shape, and the one whose claim is exactly `rate − spent`.
  #
  # `type:` DEFAULTS TO `usage`, WHICH IS THE COLUMN'S OWN DEFAULT (rules-own-the-budget spec §6
  # step 3) — so every example written before rules had a type keeps the order it had, and an
  # example that names a type is saying so on purpose. `item:` because a category may carry only ONE
  # item-less rule (`Budget#category_may_hold_one_item_less_rule`), and the give-way examples need
  # two rules of different types under one heading.
  def rate(category, amount, type: :usage, item: nil)
    create(:budget, :per_period_rate, category: category, amount: amount, rule_type: type, item: item)
  end

  # ** AN ALLOWANCE THAT KEEPS WHAT IT DOESN'T SPEND (two-shapes §12). ** `#rate`'s columns plus the
  # one that says the boundary leaves the money alone — and `created_at:` for the reason `#bill`
  # states, because unlike a rate rule this one WALKS: a fund born at real-now would visit no period
  # of this file's Feb 2026 clock and hold nothing.
  def keeps(category, amount, type: :usage, item: nil, created_at: Time.zone.local(2025, 1, 1))
    create(
      :budget,
      :keeps_unspent,
      category: category,
      amount: amount,
      rule_type: type,
      item: item,
      created_at: created_at
    )
  end

  def lane(category, name) = create(:item, category: category, name: name)

  # ** `created_at:` IS PLANTED ON EVERY ACCRUING RULE IN THIS FILE (the ruling of 2026-09-03). ** A
  # rule accrues from the LATER of its category's `funded_since` and its own birthday, and this
  # file's `today` is Feb 2026 while the factory writes rules at real-now — so a rule left alone
  # walks NO periods and holds nothing, whatever its anchor says. Rate rules are unaffected: their
  # walk is this period and no other by construction (§3.1).
  #
  # `item:` because a category may carry only ONE item-less rule
  # (`Budget#category_may_hold_one_item_less_rule`), and some examples need two bills on one category.
  def bill(category, amount:, due:, item: nil, created_at: Time.zone.local(2025, 1, 1))
    create(
      :budget,
      :one_time,
      category: category,
      amount: amount,
      anchor_date: due,
      item: item,
      created_at: created_at
    )
  end

  # A rule that rolls: its due date moves with the cycles that have gone by and with what has been
  # paid into it.
  def rolling(category, amount:, anchor:, every: 1, created_at: Time.zone.local(2025, 1, 1))
    create(
      :budget,
      category: category,
      amount: amount,
      interval_months: every,
      anchor_date: anchor,
      created_at: created_at
    )
  end

  # INCOME RAISES THE POT (§2). It lands in the user's main account, which is the only place income
  # may land.
  def income(amount, on: today)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # SPENDING LOWERS THE POT ALWAYS, and lowers a CLAIM when the category counts that day.
  def spend(category, amount, on: today)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # A BILL THAT ROLLS ONCE A YEAR: its whole face value falls due inside the current period, which is
  # what makes `Σ claims` and `Budget.steady_need` diverge.
  def annual(category, amount:, due:)
    create(
      :budget,
      category: category,
      amount: amount,
      interval_months: 12,
      anchor_date: due,
      created_at: Time.zone.local(2025, 1, 1)
    )
  end

  # ** `allocate` IS DELETED (Task 3), and with it every `create(:allocation, …)` in this file. **
  # Money into a category was the purpose ledger's writer; there is none. What puts money behind a
  # rule now is the rule itself (it accrues) or a DATED ADJUSTMENT (§3.3), which is this.
  def set_aside(rule, amount, on: today)
    create(:adjustment, rule: rule, amount: amount, date: on)
  end

  describe "#accounts" do
    it "returns only this user's accounts, by name", :aggregate_failures do
      zebra = create(:pool, :account, user: user, name: "Zebra")
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:pool, :account, user: create(:user), name: "Stranger")

      expect(presenter.accounts).to eq([ally, checking, zebra])
    end
  end

  describe "#balance_of" do
    it "is what the bank says, and for main that is the pot", :aggregate_failures do
      income(1_000)
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 250)

      expect(presenter.balance_of(checking)).to eq(750)
      expect(presenter.in_checking).to eq(750)
    end

    it "is movements only on an account that is not main", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

      expect(presenter.balance_of(ally)).to eq(600)
      expect(presenter.balance_of(checking)).to eq(400)
    end

    it "is a decimal zero, not an integer, on an empty account" do
      expect(presenter.balance_of(checking)).to be_a(BigDecimal)
    end
  end

  describe "#categories" do
    it "returns the holders in fill order and nothing else", :aggregate_failures do
      second = holder("Zebra", priority: 1)
      first = holder("Apples", priority: 1)
      create(:category, :expense, user: user, name: "Never Funded", funded_since: nil)
      create(:category, :income, user: user, name: "Salary")

      expect(presenter.categories).to eq([first, second])
    end
  end

  # ** EVERY CATEGORY WITH A ROW, WHICH IS WIDER THAN THE FILL ORDER. ** `ClaimLedger` counts every
  # rule's claim into `free`, including a rule on a category whose `funded_since` was cleared after
  # the fact — so a claim with no row would be money missing from the hero's figure with nothing on
  # the screen to explain it.
  describe "#budgeted_categories" do
    it "adds a ruled category that is not a holder, in priority order", :aggregate_failures do
      funded = holder("Groceries", priority: 1)
      rate(funded, 400)
      stranded = create(:category, :expense, user: user, name: "Coffee", priority: 2, funded_since: nil)
      rate(stranded, 35)

      expect(presenter.categories.map(&:name)).to eq(["Groceries"])
      expect(presenter.budgeted_categories.map(&:name)).to eq(["Groceries", "Coffee"])
      # ** THE BLOCK IS THERE, AND IN GIVE-WAY ORDER RATHER THAN FILL ORDER (two-shapes §3). ** This
      # read `["Groceries", "Coffee"]` off `#period_rows`, which was fill order; the section is the
      # give-way walk grouped back now, so the category that would be funded LAST is the one that
      # goes without FIRST and leads the section. Both types are `usage` here, so the ranking is the
      # category half of the key alone: Coffee's priority 2 gives way before Groceries' priority 1.
      expect(presenter.category_blocks.map(&:name)).to eq(["Coffee", "Groceries"])
    end
  end

  describe "#overdrawn_accounts" do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "names the accounts below zero and no others", :aggregate_failures do
      income(500)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 900, date: today, kind: :transfer)

      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
      expect(presenter.overdraft_for(checking)).to eq(400)
    end

    it "is empty when every account is in the black" do
      income(10)

      expect(presenter.overdrawn_accounts).to be_empty
    end

    # THE WHOLE REASON THIS READER EXISTS: the purpose side can be perfectly in order while the BANK
    # is overdrawn. PLANTED — a $1,000-a-period rule with $1,500 spent claims `max(0, 1,000 − 1,500)`
    # = $0.00 (§3.1), so nothing is claimed at all, and $500 of real debt renders nowhere unless a
    # reader asks for it by name.
    it "reports a debt no claim figure contains", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 1_000)
      spend(groceries, 1_500)

      expect(presenter.total_claims).to eq(0)
      expect(presenter.balance_of(checking)).to eq(-500)
      expect(presenter.overdrawn_accounts.map(&:name)).to eq(["Checking"])
    end
  end

  # ── THE HERO CARD'S READERS (answers-first §§2-3, on computed-claims' terms) ───────────────────

  describe "#in_checking" do
    # THE NUMBER THE BANK APP SHOWS, and it is `AccountLedger#pot` rather than a sum of accounts:
    # only main carries the entry side of the physical ledger (§2), so a second account's money is
    # not in checking however much of it there is.
    it "is the pot, not the user's money everywhere", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(400)
      expect(presenter.balance_of(ally)).to eq(600)
    end

    it "is a decimal zero for a user whose account holds nothing", :aggregate_failures do
      expect(presenter.in_checking).to eq(0)
      expect(presenter.in_checking).to be_a(BigDecimal)
    end
  end

  describe "#free_to_spend" do
    # ARCHETYPE 1: the fresh user. Nothing in, nothing claimed — and the card still renders, so every
    # figure on it has to be a real zero rather than a nil the view guards.
    it "is a decimal zero all the way down for a fresh user", :aggregate_failures do
      expect(presenter.free_to_spend).to eq(0)
      expect(presenter.free_to_spend).to eq(presenter.in_checking)
      expect(presenter.free_to_spend).to be_a(BigDecimal)
    end

    # ARCHETYPE 2: the pot less the claims. PLANTED — $2,000 in, one $400-a-period rule with nothing
    # spent, so `claim = max(0, 400 − 0)` = $400.00 (§3.1) and `free = 2,000 − 400` = **$1,600.00**.
    it "is the pot less the claims when it is all in checking", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.in_checking).to eq(2_000)
      expect(presenter.total_claims).to eq(400)
      expect(presenter.free_to_spend).to eq(1_600)
    end

    # ** MONEY IN ANOTHER ACCOUNT IS NOT IN THE SUBTRACTION AT ALL (two-shapes §2, Henry's ruling of
    # 2026-09-05). ** THE SAME FIXTURE with $1,500 walked over to Ally: the claims are untouched and
    # the pot is $500, so `free` is **$100.00**. It was `min(pot, total_money − Σ claims)` — which
    # answered $500, the WHOLE pot, with $400 of rules claiming against it — because the other
    # account's money was folded into the subtraction and then capped away. The two hero figures were
    # the same number for every user whose savings covered their rules.
    it "does not count another account's money, and does not cap at the pot", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(500)
      expect(presenter.total_claims).to eq(400)
      expect(presenter.free_to_spend).to eq(100)
      expect(presenter.other_accounts_total).to eq(1_500)
    end

    # ARCHETYPE 3: free below zero, NEVER clamped (§4: a signal, not a refusal). $150 in against a
    # $400 claim — the rules ask for $250 more than exists, and the card has to say so.
    it "states the gap rather than reporting nothing left", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.free_to_spend).to eq(-250)
    end

    # THE PURE OVERSPEND. No rules at all, so nothing is claimed, while $100 of spending has taken the
    # pot below zero. `free` is simply -$100.00 — the honest sentence, with no branch to get wrong.
    it "is negative for a period whose spending has taken the pot under", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 100)

      expect(presenter.total_claims).to eq(0)
      expect(presenter.free_to_spend).to eq(-100)
    end

    # ARCHETYPE 4: the physical overdraft, with a claim still standing beside it. PLANTED — $1,000 in,
    # a $1,000-a-period rule, $600 spent on it: `claim = max(0, 1,000 − 600)` = **$400.00** and the pot
    # is `1,000 − 600` = **$400.00**, so `free = 400 − 400` = $0.00. Spend $200 more and both go under
    # together, which is the next example's job.
    it "counts the spending against the claim as well as against the pot", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 1_000)
      spend(groceries, 600)

      expect(presenter.in_checking).to eq(400)
      expect(presenter.total_claims).to eq(400)
      expect(presenter.free_to_spend).to eq(0)
    end

    # THE SAME SHAPE PAST THE END: $1,500 spent against a $1,000 rule. The claim clamps to $0.00 and
    # the $500 excess reduces `free` directly (§3.1) rather than sitting anywhere — pot and free are
    # both **−$500.00**, and a claim that had gone negative instead would read −$1,000 here.
    it "is negative beside a negative pot", :aggregate_failures do
      income(1_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 1_000)
      spend(groceries, 1_500)

      expect(presenter.in_checking).to eq(-500)
      expect(presenter.total_claims).to eq(0)
      expect(presenter.free_to_spend).to eq(-500)
    end
  end

  # ** `#claims_outrun_the_money?` AND `#free_cap_bound?` ARE DELETED, AND THEIR EXAMPLES WITH THEM
  # (two-shapes spec §2/§7). **
  #
  # Both existed because of the `min`. `free = min(pot, total_money − Σ claims)` could go below zero
  # for two unrelated reasons — the claims outrun the money, or the money is in another account — and
  # the SIGN could not tell them apart, so the first predicate asked the sign of the uncapped half and
  # the second asked which of the `min`'s two terms had bound. Four examples pinned the combinations,
  # including the one that forbade spelling either as the other (a pot of −$500 against an uncapped
  # −$100 was cap-bound AND genuinely out of money).
  #
  # `free = pot − Σ claims` has ONE cause per sign. `#short?` — `free.negative?` — is the whole of the
  # question, and it is what `#uncovered_claims` and the strip now gate on; the arm table below is two
  # arms rather than four for the same reason. The money in other accounts is a separate fact with a
  # separate reader (`#money_parked_elsewhere?`), never a term in this figure.

  # ** THE CAUSES THE SUBLINE ASSERTS. ** The signs of the two figures say WHICH WAY the arithmetic
  # went and never WHY, and the cap's identity is where that bites:
  #
  #     unclaimed − pot  =  Σ other accounts  −  Σ claims
  #
  # Two terms where the allocation era had three. Each predicate below is measured against a fixture
  # that establishes it and one that does not, because the failure this discipline exists to kill is
  # a sentence that is true-SOUNDING rather than one that is missing.
  describe "the subline's causes" do
    describe "#money_parked_elsewhere?" do
      # A USER WITH ONE ACCOUNT HAS NOTHING PARKED ANYWHERE, whatever else is true of them. PLANTED
      # at the answers-first review's own M-1 shape: $1,000 in, a $900 rate rule, $1,100 spent —
      # `claim = max(0, 900 − 1,100)` = $0.00 and the pot is −$100, so `free` is −$100 and the card's
      # red arm has no "move some in" to offer.
      it "is false where a category was overspent on a single account", :aggregate_failures do
        groceries = holder("Groceries", priority: 1)
        income(1_000)
        rate(groceries, 900)
        spend(groceries, 1_100)

        expect([presenter.in_checking, presenter.total_claims]).to eq([-100, 0])
        expect(presenter.free_to_spend).to eq(-100)
        expect(presenter).not_to be_money_parked_elsewhere
      end

      # AN ACCOUNT THAT IS ITSELF BELOW ZERO IS NOT SOMEWHERE MONEY IS PARKED, which is why the
      # predicate is the TOTAL's sign and not `#other_accounts.any?`: Ally has walked $200 into
      # checking and is $200 overdrawn, so it is a DEBT the strip names, not a place to transfer from.
      it "is false for an account that is itself overdrawn", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_000)
        create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: today, kind: :transfer)

        expect(presenter.other_accounts.map(&:name)).to eq(["Ally"])
        expect(presenter.other_accounts_total).to eq(-200)
        expect(presenter).not_to be_money_parked_elsewhere
      end

      it "is true once that account actually holds money", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_000)
        create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: today, kind: :transfer)

        expect(presenter.other_accounts_total).to eq(600)
        expect(presenter).to be_money_parked_elsewhere
      end
    end

    # IT REPLACES `#anything_set_aside_or_spoken_for?`, whose two nouns were a HOLDING and a
    # distribution's remaining ask. `Σ claims` is one figure the ledger has already computed for
    # `free`, so this costs the card nothing it was not already paying.
    describe "#anything_claimed?" do
      # THE PURE OVERSPEND: no rule claims anything and the pot is simply below zero. This is the
      # predicate that keeps the red arm's sentence from naming a claim that does not exist — "You
      # have spent past what you had" rather than "your rules claim $X more".
      it "is false for an account that has only been spent past zero", :aggregate_failures do
        spend(create(:category, :expense, user: user, name: "Unbudgeted"), 100)

        expect(presenter.free_to_spend).to eq(-100)
        expect(presenter).not_to be_anything_claimed
      end

      it "is true while a rule claims anything at all" do
        rate(holder("Groceries", priority: 1), 400)

        expect(presenter).to be_anything_claimed
      end

      # ** A RATE RULE SPENT FLAT CLAIMS NOTHING, and that is not a bug in this predicate. ** §3.1 is
      # use-it-or-lose-it: the envelope has been used, so there is no money left for it to claim, and
      # a card saying "more is claimed than you have" over it would be naming a claim of $0.00.
      it "is false for a rate rule that has been spent to nothing", :aggregate_failures do
        income(400)
        groceries = holder("Groceries", priority: 1)
        rate(groceries, 400)
        spend(groceries, 400)

        expect(presenter.total_claims).to eq(0)
        expect(presenter).not_to be_anything_claimed
      end

      # THE ACCRUING SIDE, so the predicate is not a fact about rate rules alone. PLANTED: a $400 goal
      # due at the close of the current period — one boundary left, so §3.2's catch-up asks the whole
      # remainder and `built_up` is **$400.00** with nothing spent.
      it "is true for a goal that has accrued toward its date", :aggregate_failures do
        goal = savings_goal("Vacation", priority: 1)
        goal_rule(goal, target: 400)

        expect(presenter.total_claims).to eq(400)
        expect(presenter).to be_anything_claimed
      end
    end

    # ** `#rest_in_checking?` IS DELETED WITH THE `min` IT READ BACKWARDS (two-shapes §2/§7). ** It
    # was `in_checking > free_to_spend`, the gate on both "the rest…" sentences, and it existed
    # because `free` could equal the pot exactly (the fresh signup, where there is no rest to say
    # anything about) or fall below it for either of two reasons. `free = pot − Σ claims` makes the
    # rest ALWAYS `Σ claims`, so "is there a rest" and "is anything claimed" are one question and
    # `#anything_claimed?` is the one that survives. Its four examples went with it.

    # ** THE ARM TABLE, RE-DERIVED ROW BY ROW. ** `home/_money.html.erb` branches on these predicates
    # in this order and says a different sentence on each row; the presenter's own header states the
    # table, and this block asserts the COMBINATION rather than the predicates one at a time — which
    # is exactly how the old table's last row shipped ungated.
    #
    # ** IT WAS FOUR ARMS AND SEVEN SENTENCES, AND THE `min` IS WHAT MADE IT SO (two-shapes §2). **
    # The tuple carried `[claims outrun, free < 0, rest in checking, anything claimed, money parked]`,
    # because a negative `free` had two causes and a positive one had two shapes. `free = pot − Σ
    # claims` has one cause per sign, so the tuple is three:
    #
    #   [free < 0, anything claimed, money parked elsewhere]
    #
    # Every fixture plants literal money and every figure is re-derived by hand from §2's
    # `free = pot − Σ claims`. Both directions of every gate appear, because a gate only ever asserted
    # true would pass against a card that always printed its clause.
    describe "the free subline's arm table" do
      def arm
        [
          presenter.free_to_spend.negative?,
          presenter.anything_claimed?,
          presenter.money_parked_elsewhere?
        ]
      end

      # ARM 1, CLAIMED, NOTHING ELSEWHERE: $150 in, a $400-a-period rate rule claiming the whole 400
      # (§3.1, nothing spent). `free = 150 − 400` = −$250. The card reads "Your rules claim $250.00
      # more than checking holds. You have spent past what you had."
      it "arm 1 — the rules claim more than checking holds, with nowhere to move money from", :aggregate_failures do
        income(150)
        rate(holder("Groceries", priority: 1), 400)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([150, -250, 400])
        expect(presenter.shortfall).to eq(250)
        expect(arm).to eq([true, true, false])
      end

      # ARM 1, WITH MONEY TO MOVE IN: the same shortfall with $1,000 sitting in Ally. The second
      # sentence becomes "Move some in from your other accounts", which is the remedy the old card
      # could only reach through the cap.
      it "arm 1 — the rules claim more than checking holds, and another account has money", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_150)
        rate(holder("Groceries", priority: 1), 400)
        create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_000, date: today, kind: :transfer)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([150, -250, 400])
        expect(presenter.other_accounts_total).to eq(1_000)
        expect(arm).to eq([true, true, true])
      end

      # ARM 1, THE PURE OVERSPEND: $150 in and $300 spent on a category with no rule, so nothing is
      # claimed anywhere and the pot is −$150. `#anything_claimed?` is what keeps the headline from
      # naming rules that claim nothing.
      it "arm 1 — the money is spent past zero with no rule claiming a penny", :aggregate_failures do
        income(150)
        spend(create(:category, :expense, user: user, name: "Subscriptions"), 300)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([-150, -150, 0])
        expect(arm).to eq([true, false, false])
      end

      # ** ARM 2, AND IT IS THE ROW THE CAP USED TO ERASE. ** $2,000 in, a $400 rate rule, $1,500
      # walked to Ally: `free = 500 − 400` = **$100.00**, and the card says "$400.00 of checking is
      # claimed by your rules, and $1,500.00 sits in 1 other account". The old figure was $500 — the
      # whole pot, with the claims invisible — because the savings covered them and the cap answered
      # the pot.
      it "arm 2 — free is positive, something is claimed, and money sits elsewhere", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(2_000)
        rate(holder("Groceries", priority: 1), 400)
        create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([500, 100, 400])
        expect(presenter.other_accounts_total).to eq(1_500)
        expect(arm).to eq([false, true, true])
      end

      # ARM 2, ONE ACCOUNT: $2,000 in, a $400 rate rule. `free` $1,600, and the card says only the
      # first half — there is nowhere else for money to be.
      it "arm 2 — free is positive and everything the user has is in checking", :aggregate_failures do
        income(2_000)
        rate(holder("Groceries", priority: 1), 400)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([2_000, 1_600, 400])
        expect(arm).to eq([false, true, false])
      end

      # ARM 2, NOTHING CLAIMED: $1,000 in, $400 walked to Ally, no rules at all. `free = 600 − 0` =
      # $600 and the claimed clause reads $0.00, which is true and is the fresh-signup-with-savings
      # shape. `#money_parked_elsewhere?` is the accounts line's own sum, so the card cannot claim
      # money the line below it shows as absent.
      it "arm 2 — nothing is claimed and money is parked", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_000)
        create(:account_movement, from_pool: checking, to_pool: ally, amount: 400, date: today, kind: :transfer)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([600, 600, 0])
        expect(arm).to eq([false, false, true])
      end

      # ARM 2, THE FRESH SIGNUP: $1,000 in, one account, no rule. Both figures are the same number
      # because nothing is claimed at all and there is nowhere else for anything to be.
      it "arm 2 — nothing is claimed and nothing is anywhere else", :aggregate_failures do
        income(1_000)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([1_000, 1_000, 0])
        expect(arm).to eq([false, false, false])
      end

      # AN OVERDRAWN SECOND ACCOUNT IS NOT SOMEWHERE MONEY IS PARKED, which is why the gate is the
      # TOTAL's sign: $200 walked IN from an Ally that is now $200 overdrawn is a DEBT the strip
      # names, not a place to transfer from.
      it "arm 2 — an overdrawn second account is not money parked", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_000)
        create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: today, kind: :transfer)

        expect([presenter.in_checking, presenter.free_to_spend, presenter.total_claims]).to eq([1_200, 1_200, 0])
        expect(presenter.other_accounts_total).to eq(-200)
        expect(arm).to eq([false, false, false])
      end
    end
  end

  describe "#period_progress" do
    # DAY X OF Y OFF `#period_range`, which is `User#period_containing` — the one window every other
    # screen reads. `today` is the presenter's, planted, so nothing here depends on the day the suite
    # runs (CLAUDE.md's third flake cause).
    it "counts today into the declared period", :aggregate_failures do
      progress = described_class.new(user: user, today: Date.new(2026, 2, 12)).period_progress

      expect([progress.first, progress.last]).to eq([Date.new(2026, 2, 6), Date.new(2026, 2, 19)])
      expect([progress.day, progress.days]).to eq([7, 14])
      expect(progress.days_left).to eq(7)
      expect(progress.percent).to eq(50)
    end

    # THE FIRST DAY AND THE LAST, so the fraction cannot be off by one at either end: day 1 of 14 is
    # not zero elapsed periods of progress, and the closing day is full rather than one short.
    it "runs from the opening day to the closing one", :aggregate_failures do
      opening = described_class.new(user: user, today: Date.new(2026, 2, 6)).period_progress
      closing = described_class.new(user: user, today: Date.new(2026, 2, 19)).period_progress

      expect([opening.day, opening.days_left, opening.percent]).to eq([1, 13, 7])
      expect([closing.day, closing.days_left, closing.percent]).to eq([14, 0, 100])
    end

    # Nil for a user who has declared no period, the same gate `#period_range` already applies:
    # `User#period_containing` falls back to the calendar month, which is right for a normaliser and a
    # lie on a card that would print a boundary nobody set.
    it "is nil before a period is declared" do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(presenter.period_progress).to be_nil
    end
  end

  # ── THE RUNWAY (two-shapes spec §3) ────────────────────────────────────────────────────────────
  #
  # ONE TICK PER DATED RULE FALLING DUE INSIDE THIS PERIOD, at its own day of it. Every position
  # below is re-derived in its example's comment from the grid the example declares — the arithmetic
  # is `(due − period opens) + 1` over `Progress#days`, and a literal nobody can re-derive is a pin
  # that cannot be maintained.
  describe "#runway" do
    # THE CATEGORY EVERY EXAMPLE IN THIS GROUP PLANTS ITS BILLS ON, funded TODAY so §3.2's walk visits
    # exactly ONE period: every figure below is then `target ÷ periods_left` with nothing behind it,
    # which is what makes the tick states derivable in a comment rather than by running the walk.
    let(:utilities) { holder("Utilities", priority: 1, funded_since: today) }

    # A ONE-TIME BILL BORN TODAY ON THAT CATEGORY. `created_at:` is planted for the ruling of
    # 2026-09-03 — a rule accrues from the LATER of its category's funding date and its own birthday,
    # and this file's clock is Feb 2026 while the factory writes at real-now.
    def due_on(category, amount:, due:, item_name: nil)
      bill(
        category,
        amount: amount,
        due: due,
        item: item_name && lane(category, item_name),
        created_at: Time.zone.local(2026, 2, 6)
      )
    end

    # A BILL DUE INSIDE THE PERIOD, ON THE FILE'S OWN BIWEEKLY GRID. Feb 6–19 is fourteen days and
    # today is the opening day; Feb 14 is `14 − 6 + 1` = **day 9**, so `round(9 ÷ 14 × 100)` = **64%**
    # along the ruler.
    #
    # THE MONEY IS THERE, so the tick is ready: the category is funded today and the rule is born
    # today, so §3.2's walk visits ONE period, `periods_left` is 1 against a date inside it, and the
    # catch-up share is the whole $120.
    it "puts a tick on the day its rule falls due", :aggregate_failures do
      income(2_000)
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 14))

      runway = presenter.runway
      tick = runway.ticks.sole

      expect([runway.day, runway.days]).to eq([1, 14])
      expect(tick.day_index).to eq(9)
      expect(tick.percent).to eq(64)
      expect(tick.amount).to eq(120)
      expect(tick.label).to eq("Utilities")
      expect(tick).to be_ready
    end

    # ** A FUND DRAWS NO TICK, BECAUSE A TICK IS A DAY (two-shapes §12). ** The runway's ruler is the
    # period and its marks are the days money is needed on; a rule that keeps what it doesn't spend
    # has none — `ClaimCalculator#next_due_on` is nil for it — so there is nothing to place. Asserted
    # beside a bill that DOES draw one, so a runway that had simply stopped drawing ticks could not
    # pass.
    it "draws no tick for a fund, beside a bill that draws one", :aggregate_failures do
      income(2_000)
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 14))
      keeps(holder("Pet Care", priority: 2), 510, created_at: Time.zone.local(2026, 2, 6))

      expect(presenter.runway.ticks.map(&:label)).to eq(["Utilities"])
      expect(presenter.runway.due_total).to eq(120)
    end

    # ** THE SAME RULE ON A MONTHLY GRID, AND ONLY THE GRID MOVES. ** Anchored on the 1st, the period
    # containing Feb 6 is Feb 1–28 — twenty-eight days, today day **6** — and a bill due Feb 21 is
    # `21 − 1 + 1` = **day 21**, so `round(21 ÷ 28 × 100)` = **75%**. The same $120 on the same
    # afternoon sits at 64% of one grid and 75% of the other, which is the whole reason the position
    # is read off `User#period_containing` and never off a month.
    it "places a rule by the grid its owner declared, not by the month", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      income(2_000)
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 21))

      runway = presenter.runway
      tick = runway.ticks.sole

      expect([runway.day, runway.days]).to eq([6, 28])
      expect([runway.first, runway.last]).to eq([Date.new(2026, 2, 1), Date.new(2026, 2, 28)])
      expect(tick.day_index).to eq(21)
      expect(tick.percent).to eq(75)
    end

    # ** READY AND SHORT, SIDE BY SIDE, WITH THE TOTAL AND THE NAMED LIST. ** Two bills due inside
    # the period: Electric's $120 is knocked to $80 by a −$40 adjustment dated inside the period, and
    # Water's $30 is whole. `due_total` is the two TARGETS ($150) — what has to be there before the
    # period closes, not what is missing — and `short` names only the one that is.
    it "tells ready from short, totals the day's asks and names the gap", :aggregate_failures do
      income(2_000)
      set_aside(due_on(utilities, amount: 120, due: Date.new(2026, 2, 14), item_name: "Electric"), -40)
      due_on(utilities, amount: 30, due: Date.new(2026, 2, 18), item_name: "Water")

      runway = presenter.runway

      # THE PAIR, TOGETHER: a label matched to the wrong state would pass two separate assertions.
      expect(runway.ticks.map { |tick| [tick.label, tick.state] }).to eq([["Electric", :short], ["Water", :ready]])
      expect(runway.due_total).to eq(150)
      expect(runway.short.map(&:label)).to eq(["Electric"])
      expect(runway.short.sole.gap).to eq(40)
    end

    # ** A PAID ONE-OFF DRAWS NO TICK, AND CONTRIBUTES NOTHING TO THE DUE TOTAL (this task's carry
    # (a)). ** A one-time bill's occurrence NEVER rolls — there is no interval to roll onto — so its
    # date stays inside this period for ever after the money has gone out, and the tick it drew was
    # RED: paying the bill empties the fund, and `#fund_short?` read the emptiness as a shortfall.
    # The pace line then told the user money was still due on a bill they had already paid.
    #
    # BOTH DIRECTIONS ON ONE FIXTURE, because a reader that dropped every tick would pass the second
    # half alone: the same rule draws a ready tick worth $120 before the payment and nothing after.
    it "draws no tick for a one-off that has been paid", :aggregate_failures do
      income(2_000)
      bill_item = lane(utilities, "Water")
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 14), item_name: nil)
      before_payment = presenter.runway

      expect(before_payment.ticks.sole).to be_ready
      expect(before_payment.due_total).to eq(120)

      create(:entry, item: bill_item, amount: 120, date: Date.new(2026, 2, 10))
      after = described_class.new(user: user, today: today).runway

      expect(after.ticks).to be_empty
      expect(after.due_total).to eq(0)
    end

    # ** AND IT IS NEITHER SHORT NOR TROUBLE, so the strip stays silent about it. ** `#short?` is
    # what colours a tick red and what the pace line's "$X short" clause reads; `#trouble?` is what
    # puts a rule in the strip at all. A one-off whose money has gone out is neither — it is DONE —
    # and `ClaimLine#paid?` is the one reading of that.
    it "calls a paid one-off neither short nor trouble", :aggregate_failures do
      income(2_000)
      bill_item = lane(utilities, "Water")
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 14), item_name: nil)
      create(:entry, item: bill_item, amount: 120, date: Date.new(2026, 2, 10))

      line = presenter.give_way_order.sole

      expect(line).to be_paid
      expect(line.paid_on).to eq(Date.new(2026, 2, 10))
      expect(line).not_to be_short
      expect(line).not_to be_trouble
      expect(presenter.troubles).to be_empty
    end

    # ** A ONE-OFF PAID ABOVE ITS TARGET IS PAID *AND* OVER, AND THAT IS THE RULING (fix round
    # MED-2). ** The narrowing carry (a) took is `#short?` and `#overdue?` — both were readings of a
    # date that cannot roll. `#over?` is NOT narrowed with them: "spent past what the rule had" is a
    # different fact and it survives the payment, because the excess left checking and no rule
    # reserved it. So the row says `paid <date>` while the strip says `over by $30.00`, at the same
    # time, about the same rule — two true sentences about two different things.
    #
    # PLANTED: a $120 bill due Feb 14, paid $150 on Feb 10. The walk caps the accrual at the $120
    # target and then settles $150 against it, so `walk.raw` is −$30 and `#over_by` is $30.
    it "calls a one-off paid above its target both paid and over", :aggregate_failures do
      income(2_000)
      bill_item = lane(utilities, "Water")
      due_on(utilities, amount: 120, due: Date.new(2026, 2, 14), item_name: nil)
      create(:entry, item: bill_item, amount: 150, date: Date.new(2026, 2, 10))

      line = presenter.give_way_order.sole

      expect(line).to be_paid
      expect(line).not_to be_short
      expect(line).to be_over
      expect(line.over_by).to eq(30)
      expect(presenter.troubles.map(&:kind)).to eq([:over])
    end

    # A PERIOD WITH NOTHING DUE IS THE ORDINARY ONE, and it still has a runway: the rail, today's
    # mark and the pace line are the answer, and a rate rule is not a day.
    it "draws a period with nothing due and no ticks", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      runway = presenter.runway

      expect(runway.ticks).to be_empty
      expect(runway).not_to be_any_due
      expect(runway.due_total).to eq(0)
    end

    # ** THE WINDOW, BOTH DIRECTIONS. ** A date in the NEXT period is not on this ruler (Feb 26 is
    # past Feb 19), and neither is one already gone: an overdue bill's day is in a period that has
    # ended, so there is no point on this line for it to sit on — the trouble strip is where a date
    # already missed belongs, and it is asserted here so the absence is not read as an omission.
    it "leaves out a date in the next period and one already gone", :aggregate_failures do
      income(2_000)
      later = holder("Insurance", priority: 1, funded_since: today)
      bill(later, amount: 200, due: Date.new(2026, 2, 26), created_at: Time.zone.local(2026, 2, 6))
      missed = holder("Rent", priority: 2, funded_since: Date.new(2026, 1, 2))
      bill(missed, amount: 900, due: Date.new(2026, 2, 2), created_at: Time.zone.local(2026, 1, 2))

      expect(presenter.runway.ticks).to be_empty
      expect(presenter.troubles.map(&:kind)).to include(:overdue)
    end

    # NO PERIOD, NO PICTURE — `#period_progress`'s own refusal, for the same reason: a runway is a
    # picture OF a period, and a calendar month nobody declared would be thirty invented days.
    it "is nil before a period is declared" do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(presenter.runway).to be_nil
    end
  end

  # ── THE PACE LINE (§3), WHICH IS TWO ARMS OF ONE QUESTION ─────────────────────────────────────
  describe "#pace_line" do
    # FREE ABOVE ZERO: what a day may cost for the rest of the period. PLANTED — $2,000 in with a
    # $400 rate rule claiming its whole rate leaves `free` **$1,600**, and today is day 1 of 14, so
    # thirteen days remain: `1,600 ÷ 13` = **$123.08**.
    it "spreads what is free over the days that are left", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      pace = presenter.pace_line

      expect(pace).to be_fine
      expect(pace.amount).to eq(123.08)
    end

    # ** THE LAST DAY IS THE FLOOR, AND IT IS THE CLOSING DAY RATHER THAN A GUARD. ** `days_left` is
    # zero on Feb 19 — the user still has today, and today is the whole of what is left — so the
    # divisor floors at one and the sentence reads the whole $1,600 for the day. Dividing by zero
    # would raise on the one afternoon the sentence matters most.
    it "puts the whole of what is free on today when the period closes today", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      pace = described_class.new(user: user, today: Date.new(2026, 2, 19)).pace_line

      expect(pace).to be_fine
      expect(pace.amount).to eq(1_600)
    end

    # FREE BELOW ZERO: the SAME figure the shortfall strip has always printed, and the two panels
    # render one sentence off this object now (`HomeHelper#pace_words`). PLANTED — $150 in against a
    # $400 rate rule is `free` −$250 over thirteen days: `250 ÷ 13` = **$19.23**.
    it "hands the shortfall's own pace back when free is under", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)

      pace = presenter.pace_line

      expect(pace).not_to be_fine
      expect(pace.amount).to eq(19.23)
      expect(pace.amount).to eq(presenter.per_day_pace)
    end

    # NIL BEFORE A PERIOD IS DECLARED — there is no "rest of the period" to spread anything over,
    # which is `#per_day_pace`'s own refusal asked of both arms.
    it "is nil before a period is declared" do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(presenter.pace_line).to be_nil
    end
  end

  # ** ONE `ClaimLedger` PER RENDER (computed-claims §3.3), PINNED BY STRICT EQUALITY. ** The house
  # idiom (distribution_clock_spec, ledger_sharing_spec) — schema and transaction chatter excluded.
  describe "the screen's query cost" do
    def count_statements(&block)
      statements = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      statements
    end

    # EVERYTHING A RENDERED HOME ASKS FOR, in the order the page asks it — the money column's own
    # readers, then the three panels below it. Split in two because one method asking a dozen
    # questions of one object is past rubocop's ABC limit, not because the halves mean anything
    # separately.
    def read_the_screen
      read_the_money_column
      read_screen_for(presenter)
    end

    # ** `#claimed_percent` AND `#other_accounts` JOINED THE LIST WITH THE TILES (two-shapes §3). **
    # The bar's fraction and the chips that name the accounts are two new readers on the one panel a
    # cost pin has always covered, and a reader the pin never calls is a reader free to open a ledger
    # of its own without any figure moving. Neither costs a statement: the fraction is `total_claims`
    # over `#in_checking` (both already read), and the chips are `#accounts`, which the overdraft
    # walk fetched.
    def read_the_money_column
      presenter.in_checking
      presenter.free_to_spend
      presenter.claimed_percent
      presenter.money_parked_elsewhere?
      presenter.anything_claimed?
      presenter.other_accounts
      presenter.period_progress
    end

    # ONE CATEGORY, `count` RULES: the first names no item (the catch-all lane) and the rest name one
    # each (the item lane), so BOTH of the claim ledger's two spending statements run at every size
    # and the comparison is not measuring a lane appearing.
    #
    # ** EVERY SHAPE A ROW CAN BE, AND NOT RATE RULES ALONE (fix wave — Task 2's deferred minor). **
    # This planted `:per_period_rate` at both sizes, which is the ONE shape whose row costs nothing
    # extra by construction: a rate rule's walk is a single period and it never reaches `#settled?`
    # or `#settled_on`. A reader that queried per DATED rule — or per settled one — was therefore
    # invisible to a pin whose whole subject is per-rule cost. The ladder is mixed now and it is
    # PROPORTIONAL: two rules are a catch-all rate and one unpaid one-off, six are those plus two
    # more item rates and two PAID one-offs, so the N side carries three dated rules to the small
    # side's one and `#settled_on`'s pass over the spending rows runs twice more.
    #
    # STILL STRICT `eq`, and it holds — measured. `Budget.steady_need`'s one-off arm builds a
    # `ClaimCalculator` per rule, which was the reason this fixture avoided dated rules; the ledger
    # the screen already holds answers it without a second statement, which is exactly the claim the
    # pin should have been making all along.
    def rules_on_one_category(count)
      category = holder("Pet Care", priority: 1)
      rate(category, 400)
      one_off(category, "Bill 0", amount: 300)
      (count - 2).times do |n|
        if n.even?
          create(:budget, :per_period_rate, category: category, amount: 50, item: lane(category, "Lane #{n}"))
        else
          one_off(category, "Bill #{n}", amount: 90, paid: true)
        end
      end
      category
    end

    # ONE DATED RULE ON ITS OWN LANE, optionally already settled. A payment of the whole amount on a
    # day the walk counts is what `ClaimCalculator#settled?` reads, and `#settled_on` then makes a
    # second pass over those rows — the reader a rate-only fixture could never reach.
    def one_off(category, name, amount:, paid: false)
      item = lane(category, name)
      bill(category, amount: amount, due: today + 10.days, item: item)
      create(:entry, item: item, amount: amount, date: today) if paid
    end

    # ** 1-vs-N: SIX RULES COST EXACTLY WHAT TWO COST. ** Same categories, same accounts, same
    # spending — so any difference at all is PER-RULE, which is what a second `ClaimLedger`, or a
    # calculator built inside a row, would produce. Strict equality, not "no more than": a pin that
    # allowed slack would not notice the ledger being rebuilt once per rule.
    def cost_of(count)
      Category.find_by(name: "Pet Care")&.destroy!
      rules_on_one_category(count)
      count_statements { read_screen_for(described_class.new(user: user, today: today)) }
    end

    it "costs the same for six rules on one category as for two", :aggregate_failures do
      income(2_000)

      expect(cost_of(6)).to eq(cost_of(2))
      expect(Budget.for_user(user).count).to eq(2)
      # THE SMALL SIDE IS THE ONE LEFT STANDING (`#cost_of` destroys and replants), and naming its
      # shapes is what stops the ladder quietly reverting to rate rules at both ends.
      expect(Budget.for_user(user).map(&:claim_shape)).to contain_exactly(:rate, :dated)
    end

    # ** THE STRIP'S OWN READERS ARE IN THE LIST (fix round 2 — LOW-2). ** A cost pin is only as
    # honest as the reader list it walks, and `_shortfall.html.erb` grew four readers across fix
    # round 1 that this method did not name: `#shortfall` (HIGH-1's headline figure),
    # `#other_accounts_total` (arm 3's "sitting outside checking" sentence), `#per_day_pace` (said on
    # every arm) and `#uncovered_remainder` (LOW-1's last line). A reader the pin never calls is a
    # reader free to open a ledger of its own without either figure moving.
    #
    # THE FIGURES DID NOT MOVE FOR THOSE FOUR, AND THAT IS THE POINT — 19 and 18 then, 16 and 15 once
    # the fix wave dropped `Budget.steady_need`'s own three, 15 and 14 now (see the count below). All
    # four are pure over state
    # the earlier lines have already fetched: `#shortfall` is `-free_to_spend`, `#uncovered_remainder`
    # is that figure less the sum of a memoised list, `#per_day_pace` divides it by `#period_progress`
    # (the user's own cadence columns, no query), and `#other_accounts_total` sums `#balance_of` over
    # `#accounts` — the statement `#in_checking` has already run and the ledger has already memoised.
    def read_screen_for(other)
      other.in_checking
      other.free_to_spend
      other.shortfall
      other.other_accounts_total
      other.per_day_pace
      other.pace_line
      other.runway
      other.category_blocks
      other.unbudgeted_rows
      other.troubles
      other.uncovered_claims
      other.uncovered_remainder
      read_the_foot_of_the_page(other)
    end

    # ** THE ACCOUNTS LINE AND THE ONBOARDING CARDS, WHICH THE PIN DID NOT WALK (fix round 1 —
    # LOW-1). ** `index.html.erb` calls `#onboarding_accounts` on every render and
    # `_accounts_line.html.erb` calls `#collapsed_accounts`; both go through `#onboarding?` to
    # `#awaiting_opening_balance?`, which runs `Category.opening_balance.exists?` — a real statement
    # that no example in this block was counting. A reader the pin never calls is a reader free to
    # open a ledger of its own without either figure moving, which is the whole point of the block.
    def read_the_foot_of_the_page(other)
      other.collapsed_accounts
      other.onboarding_accounts
    end

    # THE SECOND COUNT IS THE ONE THAT PINS THE DESIGN: every figure on this screen is composed from
    # readers the presenter already holds, so once anything has been read, reading all of it costs
    # nothing. A reader added here that opened a ledger of its own would fail this and not the first.
    it "reads the whole screen a second time for nothing at all", :aggregate_failures do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)
      spend(create(:category, :expense, user: user, name: "Subscriptions"), 32)

      expect(count_statements { read_the_screen }).to be_positive
      expect(count_statements { read_the_screen }).to eq(0)
    end

    # FIFTEEN, AND EACH ONE IS NAMED — a bare number is a pin nobody can maintain:
    #
    #    1-2. `AccountLedger#entry_side`'s income and expense SUMs — the pot's own term, memoised in
    #         that class (it ran three times over before, once for the hero's figure, once inside
    #         `#total_money` and once for the overdraft walk).
    #    3-4. its two grouped movement sums, in and out.
    #      5. `ClaimLedger#rules` — every rule the user owns …
    #    6-7. … and its `:item, category: :user` preload, one statement each.
    #      8. the claim ledger's CATCH-ALL spending lane. (The ITEM lane is absent here: no rule on
    #         this fixture names one, and the ledger does not query for an empty id list.)
    #      9. its adjustment lane.
    #     10. `#accounts` — the user's accounts by name, for the money column's chips, the accounts
    #         line and the overdraft walk.
    #     11. `#categories` — the holders in fill order …
    #     12. … and its `:budgets` preload, which is also what `Category#budgeted?` reads when
    #         `#unruled_holders` partitions them.
    #     13. `#unbudgeted_spending_this_period` — the entry sum read for its NULL answer.
    #     14. `#unbudgeted_rows`' name-ordered fetch of the categories those ids name.
    #     15. `Category.opening_balance.exists?` — onboarding step 3's latch, reached through
    #         `#collapsed_accounts` / `#onboarding_accounts` (the accounts line and the cards under
    #         it). ONE statement however many accounts the user has: `#opening_balance_recorded?` is
    #         memoised with `defined?`, and every account but main is answered `false` by the first
    #         half of `#awaiting_opening_balance?` before the latch is ever asked.
    #
    # ** NOTHING ON THIS LIST IS THE RUNWAY OR THE BLOCKS. ** Both are readings of `#claim_lines`,
    # which is lines 5-9 already paid for: a tick is a dated line placed on `#period_progress` (the
    # user's own cadence columns, no query) and a block is `#give_way_order` grouped back. A reader
    # that had opened a ledger of its own would move this number, which is what the pin is for.
    #
    # ** IT WAS NINETEEN, THEN SIXTEEN, THEN FIFTEEN, THEN FOURTEEN WITH THE BLOCKS (§3) — AND IT IS
    # FIFTEEN AGAIN BECAUSE THE PIN GREW A READER, NOT BECAUSE THE SCREEN DID (fix round 1 — LOW-1).
    # ** Line 15 was always run by a rendered Home; this block simply never walked the two readers
    # that reach it. The blocks' own saving (line 15 of the old list, `#holder_spending_this_period`)
    # is real and unchanged — see the rule-less-holder example below, which is what it costs there.**
    # The three that left first were `Budget.steady_need`'s own — its
    # `for_user(user).includes(:item, category: :user)` re-fetched rules, categories and users this
    # screen already held — and it takes the page's `ledger:` now, so lines 5-7 answer for it. The
    # SIXTEENTH was `ClaimLedger#total_money`'s fetch of the user's accounts: `free` was
    # `min(pot, total_money − Σ claims)` and read it; `free = pot − Σ claims` does not. The FIFTEENTH
    # is `#holder_spending_this_period`, and it left because its last reader did: a per-CATEGORY
    # spending sum was what `#period_rows` printed, and a per-RULE row reads its own lane off the
    # ledger. It still runs for the one shape that needs it — see the example below.
    it "costs fifteen statements for a whole render" do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)
      spend(create(:category, :expense, user: user, name: "Subscriptions"), 32)

      expect(count_statements { read_the_screen }).to eq(15)
    end

    # THE UNBUDGETED FETCH IS CONDITIONAL, and this is what says so: the same screen with nothing
    # unbudgeted spent on it costs one fewer, because `#unbudgeted_rows` returns without querying for
    # records nothing named.
    it "costs one fewer when nothing unbudgeted was spent this period" do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)

      expect(count_statements { read_the_screen }).to eq(14)
    end

    # ** AND THE HOLDER SUM IS CONDITIONAL TOO — THE OTHER DIRECTION OF THE STATEMENT THAT LEFT. **
    # The same screen plus a funded category with no rule and a receipt on it: that row's figure is
    # the one thing on Home no claim can answer, so `#holder_spending_this_period` runs, and it runs
    # ONCE for however many such categories there are.
    it "costs one more when a rule-less holder has spending" do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)
      spend(create(:category, :expense, user: user, name: "Subscriptions"), 32)
      spend(holder("Car Repairs", priority: 2), 45)

      expect(count_statements { read_the_screen }).to eq(16)
    end
  end

  # ── "THIS PERIOD" (answers-first §4, computed-claims §3.4) ────────────────────────────────────
  #
  # The bars themselves are pinned in `spec/system/home/this_period_spec.rb`, on the screen. What is
  # here is what a browser cannot reach cheaply: the WINDOW both directions, the partition between a
  # budgeted row and an unbudgeted one, the per-rule lines, and the sort key.
  describe "#category_blocks" do
    # THE WINDOW, BOTH DIRECTIONS, ON ONE CATEGORY. The period containing Feb 6 on a biweekly cadence
    # anchored Feb 6 is Feb 6–19, so the Feb 10 receipt is inside it and the Feb 2 one is not — and a
    # rate claim counts THIS period alone (§3.1), which is why the line reads $310 and not $360.
    it "counts the spending inside this period and no other", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310, on: Date.new(2026, 2, 10))
      spend(groceries, 50, on: Date.new(2026, 2, 2))

      line = presenter.category_blocks.sole.rows.sole

      expect(line.spent).to eq(310)
      expect(line.accrued).to eq(400)
      expect(line.claim).to eq(90)
    end

    # THE DENOMINATOR IS THE PER-PERIOD NORMALISER, not the sticker price: `Budget#steady_ask` turns a
    # $600-a-month rule into $276.92 of a biweekly period (26 periods a year against 12 months). This
    # rule has an anchor, so it takes §3.2's catch-up formula instead — and the figure the row prints
    # is the TARGET, which for a dated rule is the bill itself.
    it "measures a dated rule against the bill and not against a period's share", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      rolling(rent, amount: 600, anchor: Date.new(2026, 3, 1))
      line = presenter.category_blocks.sole.rows.sole

      expect(line).not_to be_rate
      expect(line.target).to eq(600)
      expect(line.next_due_on).to eq(Date.new(2026, 3, 1))
    end

    # A GOAL MEASURES AGAINST ITS TARGET (§3.4), and #filled is what it has BUILT UP rather than its
    # spending — which is what keeps the row from reading as money to spend. PLANTED: a $2,400 goal
    # due Aug 28, which is thirteen biweekly boundaries out from the current period (Feb 6, Feb 20 …
    # Aug 14 inclusive of Aug 28's own), so the walk from Jan 2025 fills it to the cap long before
    # today — the row reads **$2,400 of $2,400** at **100%**. A raid takes it off the cap, and the
    # second figure is what a partly-filled bar reads: a −$1,976 set-aside leaves $424, which is
    # `round(424 ÷ 2,400 × 100)` = **18%**.
    it "measures a goal against its target and fills the bar with what it has built up", :aggregate_failures do
      goal = savings_goal("Vacation", priority: 1)
      set_aside(goal_rule(goal, target: 2_400), -1_976)
      line = presenter.category_blocks.sole.rows.sole

      expect(line).not_to be_rate
      expect(line.target).to eq(2_400)
      expect(line.filled).to eq(424)
      expect(line.percent).to eq(18)
    end

    # ** THE UNCAPPED-FUND EXAMPLE CAME BACK WITH THE SHAPE (two-shapes §12), AND SO DID THE NIL. **
    # It was deleted under §7 with the note that "every accruing rule names a figure now, so
    # `#target` is never nil and `#denominator` never is either". §12 restores exactly one shape that
    # names none — an allowance that keeps what it doesn't spend, aiming at nothing — so the nil arm
    # is back, deliberately, and it is `ClaimLine#bar?` that answers it rather than every caller.
    #
    # THE ORIGINAL DEFECT IS WHAT THIS EXAMPLE EXISTS TO STOP COMING BACK: `#denominator` handed a
    # nil straight to `.positive?`, and every Home render for a user holding such a rule was a 500.
    #
    # PLANTED: a $510-a-period fund on a category funded Jan 2025, born the same day. The walk from
    # Jan 2025 to Feb 6 2026 is long, so what the ROW says is asserted rather than the figure — the
    # arithmetic is `claim_calculator_spec`'s — and what it says is: something built up, nothing to
    # be a fraction of, and no bar.
    it "draws a fund's row with no bar at all", :aggregate_failures do
      pet_care = holder("Pet Care", priority: 1)
      keeps(pet_care, 510)
      line = presenter.category_blocks.sole.rows.sole

      expect(line).to be_fund
      expect(line).not_to be_rate
      expect(line.target).to be_nil
      expect(line.denominator).to be_nil
      expect(line).not_to be_bar
      expect(line.percent).to eq(0)
      expect(line.filled).to be_positive
    end

    # ** AND IT IS NOT SHORT, NOT OVERDUE AND NOT IN TROUBLE, WHICH IS THE OTHER HALF OF "aiming at
    # nothing". ** `#fund_short?` is a comparison against a target, so a shape with none can never be
    # behind on anything — the strip has nothing to say about a fund until it is overSPENT.
    it "never calls a fund short or late", :aggregate_failures do
      pet_care = holder("Pet Care", priority: 1)
      keeps(pet_care, 510)
      line = presenter.category_blocks.sole.rows.sole

      expect(line.fund_short?).to be(false)
      expect(line.short?).to be(false)
      expect(line.overdue?).to be(false)
      expect(line.trouble?).to be(false)
    end

    # THE OTHER DIRECTION ON THE BAR: a goal DOES draw one, so a presenter that had simply stopped
    # drawing bars would fail here.
    it "still draws a bar for a goal", :aggregate_failures do
      goal = savings_goal("Vacation", priority: 1)
      goal_rule(goal, target: 2_400)
      line = presenter.category_blocks.sole.rows.sole

      expect(line).to be_dated
      expect(line).to be_bar
    end

    # ** A BLOCK PER CATEGORY, A ROW PER RULE — THE RULING (see HomePresenter#category_blocks; it was
    # `PeriodRow`'s until the blocks replaced it). ** A rate
    # rule beside an item-backed bill cannot honestly print one figure: `spent of rate` and `built up
    # of target` are denominated in different things and summing them would state a number that is
    # true of neither. PLANTED: $400 rate with $150 spent on an UN-ruled item → claim $250; a $600
    # bill on the Vet item, accruing since Jan 2025 against a Feb 14 2026 due date. The due date sits
    # INSIDE the current period, so §3.2's `periods_left` is 1 there and the catch-up formula closes
    # the gap exactly — `built_up` is the whole **$600.00**. The two lanes partition (§3.1), which is
    # why the rate rule's spending is $150 and not $150 plus whatever the bill's item took.
    #
    # ** THE DATED RULE LEADS, AND THAT IS `Category.rule_order` (fix wave — LOW-3). ** This file
    # asserted `[:rate, :dated]`, off a key of this presenter's own (`[item name, id]`, catch-all
    # first) while the Budget page's group and the category card both sorted the same two rules by
    # the date the row prints. One category, two screens, two orders. The model owns the key now: a
    # rule with a due date sorts ahead of one without, so the Feb 14 bill leads its category's own
    # envelope here exactly as it does everywhere else.
    it "gives a category with two rules one line each", :aggregate_failures do
      pet_care = holder("Pet Care", priority: 1)
      rate(pet_care, 400)
      bill(pet_care, amount: 600, due: Date.new(2026, 2, 14), item: lane(pet_care, "Vet"))
      spend(pet_care, 150)

      lines = presenter.category_blocks.sole.rows

      expect(lines.map(&:shape)).to eq([:dated, :rate])
      expect(lines.first.built_up).to eq(600)
      expect(lines.second.spent).to eq(150)
      expect(lines.second.claim).to eq(250)
      expect(presenter.total_claims).to eq(850)
    end

    # ** "SORTS TROUBLE FIRST AND KEEPS PRIORITY ORDER BEHIND IT" IS DELETED WITH `#period_rows`
    # (two-shapes §3). ** It asserted the section's own second ordering — a category in trouble
    # jumped the queue — and there is no second ordering: the blocks ARE `#give_way_order` grouped
    # back, which is the walk the trouble strip above them uses, so a category cannot rank one way in
    # the strip and another in the section. Trouble is said by the header TINT now
    # (`CategoryBlock#trouble?`, pinned below and on the screen in `this_period_spec`) rather than by
    # moving the block, which is the honest signal: a reader scanning for red does not have to
    # re-learn where a category went.

    # ** THE ORDER, AND IT IS THE ONE SORT (§3). ** Three categories, and every term of
    # `#give_way_key` decides something here:
    #
    #   Fun money   priority 3, one CHOICE rule   → type_rank 0, so it leads whatever its priority
    #   Groceries   priority 2, one USAGE rule    → type_rank 1, and priority 2 gives way before 1
    #   Rent        priority 1, one BILL rule     → type_rank 2, the last thing reached
    #
    # A BLOCK SITS WHERE ITS FIRST-GIVING-WAY RULE SITS, which is what the two-rule category proves:
    # Groceries carries a choice rule as well, so its FIRST line in the walk is that choice — ranked
    # between Fun money's (priority 3 gives way first) and its own usage rule — and the block
    # therefore lands second, ahead of every usage rule in the app. Its own rows keep the walk's
    # order too, choice above usage.
    it "orders the blocks by the rule of each that gives way first", :aggregate_failures do
      rate(holder("Rent", priority: 1), 400, type: :bill)
      groceries = holder("Groceries", priority: 2)
      rate(groceries, 400)
      rate(groceries, 60, type: :choice, item: lane(groceries, "Treats"))
      rate(holder("Fun money", priority: 3), 100, type: :choice)

      blocks = presenter.category_blocks

      expect(blocks.map(&:name)).to eq(["Fun money", "Groceries", "Rent"])
      expect(blocks.second.rows.map(&:stripe_type)).to eq([:choice, :usage])
      expect(blocks.second.rule_count).to eq(2)
    end

    # WHAT THE HEADER SAYS: how many rules, and what they claim BETWEEN them. PLANTED — a $400 rate
    # with $150 spent claims $250 (§3.1), and a $60 rate untouched claims $60, so the header reads
    # $310 over two rules while neither row's own figure is that number.
    it "adds a block's claims up across its rules", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      rate(groceries, 60, item: lane(groceries, "Treats"))
      spend(groceries, 150)

      block = presenter.category_blocks.sole

      expect(block.rule_count).to eq(2)
      expect(block.claimed).to eq(310)
      expect(block.claimed).to eq(presenter.total_claims)
    end

    # ── THE HEADER TINT (§3: "a category in trouble — any rule over, short or overdue") ───────────

    # ** IT IS WIDER THAN THE TROUBLE STRIP'S OWN TRIGGERS, AND THIS IS THE ROW THAT SHOWS IT. ** A
    # $120 bill due Feb 14 — inside the Feb 6–19 period — with $80 built up is short $40: nothing has
    # gone wrong (the date has not passed, nothing was overspent), so §5's strip is silent, and the
    # block tints because the money is not there for a day that is.
    #
    # PLANTED: the rule is born Feb 6 with the category funded the same day, so the walk visits ONE
    # period; a −$40 adjustment inside it takes the catch-up's $120 down to $80.
    it "tints a block whose rule is short with the day inside this period", :aggregate_failures do
      income(2_000)
      utilities = holder("Utilities", priority: 1, funded_since: Date.new(2026, 2, 6))
      rule = bill(utilities, amount: 120, due: Date.new(2026, 2, 14), created_at: Time.zone.local(2026, 2, 6))
      set_aside(rule, -40)

      block = presenter.category_blocks.sole

      expect(block.rows.sole.built_up).to eq(80)
      expect(block.rows.sole).to be_short
      expect(block).to be_trouble
      expect(presenter.troubles).to be_empty
    end

    # THE OTHER DIRECTION, so the tint cannot be satisfied by a block that always claims trouble: the
    # same bill with its money whole is ready, and nothing about it is red.
    it "leaves a block alone when its rule has the money for the day", :aggregate_failures do
      utilities = holder("Utilities", priority: 1, funded_since: Date.new(2026, 2, 6))
      bill(utilities, amount: 120, due: Date.new(2026, 2, 14), created_at: Time.zone.local(2026, 2, 6))

      block = presenter.category_blocks.sole

      expect(block.rows.sole.built_up).to eq(120)
      expect(block.rows.sole).not_to be_short
      expect(block).not_to be_trouble
    end

    # A GOAL WITH YEARS TO RUN IS NOT SHORT, WHICH IS THE HALF OF `#short?` THE DATE CARRIES. Its
    # money is missing by definition — that is what saving is — and a block tinted red for it would
    # be red for as long as the goal exists.
    #
    # PLANTED, AND THE HORIZON IS DERIVED RATHER THAN WRITTEN: the category is funded today and the
    # rule is born today, so §3.2's walk visits exactly ONE period; the due date is the close of the
    # 26th biweekly period from today (`today + 14 × 26 − 1`), which is 26 boundaries away, so the
    # catch-up share is `5,000 ÷ 26` = **$192.31** and that is the whole of what has accrued.
    it "does not call a goal with years to run short", :aggregate_failures do
      vacation = holder("Vacation", priority: 1, funded_since: today)
      goal_rule(vacation, target: 5_000, due: today + (14 * 26) - 1, created_at: Time.zone.local(2026, 2, 6))

      block = presenter.category_blocks.sole

      expect(block.rows.sole.built_up).to eq(192.31)
      expect(block.rows.sole).not_to be_short
      expect(block).not_to be_trouble
      expect(block.rows.sole.bar_state).to eq(:normal)
    end

    # ── THE ROW'S OWN VOCABULARY (§3), which `HomeHelper` renders and this pins as data ───────────

    # THE NAME IS THE LANE: the item a rule names, or the catch-all it is. `#stripe_type` is the
    # RULE's type and not its category's, which is the whole reason a block can carry two colours.
    it "names a row by its lane and stripes it by its rule's type", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      rate(groceries, 60, type: :choice, item: lane(groceries, "Treats"))

      rows = presenter.category_blocks.sole.rows

      expect(rows.map(&:name)).to eq(["Treats", "Whole category"])
      expect(rows.map(&:stripe_type)).to eq([:choice, :usage])
    end

    # THE FOUR BAR STATES, THREE OF THEM HERE AND `:short` ABOVE. A rate rule spent past its rate is
    # over ($80 of $50), spent to the penny is full ($50 of $50), and under it is normal.
    it "reads a bar state off the same figures the bar is drawn from", :aggregate_failures do
      over = holder("Dining Out", priority: 1)
      rate(over, 50)
      spend(over, 80)
      exact = holder("Coffee", priority: 2)
      rate(exact, 50)
      spend(exact, 50)
      under = holder("Groceries", priority: 3)
      rate(under, 50)

      states = presenter.category_blocks.to_h { |block| [block.name, block.rows.sole.bar_state] }

      expect(states).to eq("Dining Out" => :over, "Coffee" => :full, "Groceries" => :normal)
    end
  end

  describe "#unbudgeted_rows" do
    # ** CARRIED FROM `#period_rows` AS "keeps a rule-less holder only while it has spending"
    # (two-shapes §3). ** A holder that was funded and never given a rule used to be a BUDGETED row
    # with an empty line list, printing `spent $45.00`; an unbudgeted category printed the same
    # string from the other list. They are one fact — no rule claims these receipts — and this reader
    # answers for both now, which is why the example moved rather than being deleted. Its figures are
    # unchanged, and the second half (a holder with neither rule nor spending is absent) is the same
    # `#silent?` rule the old row carried, stated as a filter on the spending instead.
    it "keeps a rule-less holder only while it has spending", :aggregate_failures do
      spend(holder("Car Repairs", priority: 1), 45)
      holder("Someday Fund", priority: 2)

      rows = presenter.unbudgeted_rows

      expect(rows.map { |row| row.category.name }).to eq(["Car Repairs"])
      expect(rows.sole.spent).to eq(45)
      expect(presenter.category_blocks).to be_empty
    end

    # THE TWO POPULATIONS ON ONE SCREEN, IN ONE NAME ORDER — a funded holder with no rule and a
    # category nobody ever funded. They reach this list down different queries (`ENTRY_CATEGORY_ID`
    # answers for one and its NULL arm for the other), and a reader that sorted each half separately
    # would print two alphabets one after the other.
    it "sorts the funded and the never-funded into one alphabet", :aggregate_failures do
      spend(holder("Car Repairs", priority: 1), 45)
      never = create(:category, :expense, user: user, name: "Books")
      create(:entry, item: create(:item, category: never), amount: 12, date: today)

      expect(presenter.unbudgeted_rows.map { |row| row.category.name }).to eq(["Books", "Car Repairs"])
      expect(presenter.unbudgeted_rows.map(&:spent)).to eq([12, 45])
    end

    # ZERO-SPEND ROWS ARE ABSENT BY CONSTRUCTION — they never appear in the grouped sum — which is the
    # rule stated as a query rather than as a filter somebody could forget.
    it "lists only the unbudgeted categories with spending in this period", :aggregate_failures do
      spender = create(:category, :expense, user: user, name: "Subscriptions")
      create(:entry, item: create(:item, category: spender), amount: 32, date: today)
      create(:category, :expense, user: user, name: "Someday")
      stale = create(:category, :expense, user: user, name: "Old")
      create(:entry, item: create(:item, category: stale), amount: 99, date: Date.new(2026, 2, 2))

      expect(presenter.unbudgeted_rows.map { |row| row.category.name }).to eq(["Subscriptions"])
      expect(presenter.unbudgeted_rows.sole.spent).to eq(32)
    end

    # ** THE PARTITION'S ONE HARD EDGE. ** A category funded PART-WAY THROUGH this period drains
    # nothing for the receipts dated before its `funded_since` and itself for the ones after — so the
    # same category appears on both sides of `ENTRY_CATEGORY_ID`. It belongs in the budgeted list with
    # its bar, once; its pre-funding spending is nobody's claim.
    it "never lists a budgeted category as unbudgeted as well", :aggregate_failures do
      groceries = holder("Groceries", priority: 1, funded_since: Date.new(2026, 2, 8))
      rate(groceries, 400)
      spend(groceries, 20, on: Date.new(2026, 2, 7))
      spend(groceries, 30, on: Date.new(2026, 2, 9))

      expect(presenter.unbudgeted_rows).to be_empty
      expect(presenter.category_blocks.sole.rows.sole.spent).to eq(30)
    end
  end

  describe "#troubles" do
    # EACH KIND FROM AN EXISTING READER, and the list is what the strip renders from — so a trigger
    # added to the presenter and forgotten in the view, or the reverse, shows up here as a count.
    #
    # PLANTED, four kinds on one screen: Ally has walked $200 into checking and is $200 overdrawn
    # (:overdraft); a $3,000-a-period rule against $1,000 of money leaves `unclaimed` at −$2,000
    # (:shortfall, and it also makes the rules exceed the $2,400 declared income → :structural); and
    # $80 spent against a $50 rate is over by $30 (:over).
    def overspend(name, rate_amount, spent)
      holder(name, priority: 2).tap do |category|
        rate(category, rate_amount)
        spend(category, spent)
      end
    end

    it "types each trigger and orders them money-gone-first", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: today, kind: :transfer)
      income(800)
      rate(holder("Rent", priority: 1), 3_000)
      overspend("Dining Out", 50, 80)

      expect(presenter.troubles.map(&:kind)).to eq([:overdraft, :shortfall, :over, :structural])
      expect(presenter.troubles.first.subject).to eq(ally)
      expect(presenter.troubles.third.subject.category.name).to eq("Dining Out")
      expect(presenter).to be_trouble
    end

    # ** THE STRIP AND THE SECTION BELOW IT WALK ONE ORDER (fix wave — MED-1). ** `#trouble_lines`
    # walked `#budgeted_categories` — `[priority, name]`, the FILL order — while every block under it
    # is `#give_way_order` grouped back, so the two panels could rank one pair of categories opposite
    # ways. This is the pair that shows it.
    #
    # PLANTED, and each figure re-derived: Rent is a `bill` on a priority-0 category, $600 anchored
    # Jan 2 2026 against a `today` of Feb 6 — a date a month past, nothing spent, so the fund is
    # whole and the trigger is `:overdue`. Fun is a `choice` rate of $50 with $80 spent on it, on a
    # priority-1 category — `:over` by $30. FILL order ranks the categories `[0, "Rent"]` before
    # `[1, "Fun"]`; GIVE-WAY order ranks on the rule's type first (`choice` 0 before `bill` 2), so
    # the choice goes without before the rent does and Fun leads. The section says Fun, Rent — and
    # now so does the strip.
    def overdue_rent_and_overspent_fun
      create(
        :budget,
        :one_time,
        category: holder("Rent", priority: 0),
        amount: 600,
        rule_type: :bill,
        anchor_date: Date.new(2026, 1, 2),
        created_at: Time.zone.local(2025, 1, 1)
      )
      fun = holder("Fun", priority: 1)
      rate(fun, 50, type: :choice)
      spend(fun, 80)
    end

    it "lists its rows in the order the blocks below are drawn in", :aggregate_failures do
      income(2_000)
      overdue_rent_and_overspent_fun

      expect(presenter.troubles.map(&:kind)).to eq([:over, :overdue])
      expect(presenter.troubles.map { |trouble| trouble.subject.category.name }).to eq(["Fun", "Rent"])
      expect(presenter.category_blocks.map(&:name)).to eq(["Fun", "Rent"])
    end

    # ** AN OVERDUE BILL IS A DATE PAST, FUND OR NO FUND (fix round 1 — MED-1). ** This pinned the
    # opposite — "only where the fund is short" — and that was the finding: §3.2's catch-up formula
    # floors `periods_left` at 1 for a date already gone, so an unpaid bill's fund fills in ONE period
    # and the WHOLE fund is the ordinary shape of an overdue bill. The user with $600 saved for a bill
    # they never paid got silence.
    #
    # PLANTED: a $600 bill anchored Jan 2 2026 on a category funded and ruled since Jan 2025, against
    # $2,000 of income so nothing else is true. Nothing spent → the fund is whole at **$600.00**, the
    # occurrence does not roll (`cycles_paid_by` needs a whole cycle) and Jan 2 is a month behind
    # `today` (Feb 6). Spend $200 and `raw = 600 − 200` leaves **$400.00** against the same date: the
    # SAME trigger, and only the strip's sentence changes.
    def unpaid_bill
      income(2_000)
      holder("Utilities", priority: 1).tap do |utilities|
        rolling(utilities, amount: 600, anchor: Date.new(2026, 1, 2), every: 6)
      end
    end

    it "fires the overdue trigger on a date past with the fund whole", :aggregate_failures do
      unpaid_bill

      expect(presenter.troubles.map(&:kind)).to eq([:overdue])
      expect(presenter.troubles.sole.subject.built_up).to eq(600)
      expect(presenter.troubles.sole.subject).not_to be_fund_short
    end

    # THE SAME TRIGGER WITH THE FUND SHORT, and only `#fund_short?` — the strip's sentence — differs.
    it "fires the same trigger with the fund short, and says the gap", :aggregate_failures do
      spend(unpaid_bill, 200)

      expect(presenter.troubles.map(&:kind)).to eq([:overdue])
      expect(presenter.troubles.sole.subject.built_up).to eq(400)
      expect(presenter.troubles.sole.subject).to be_fund_short
      expect(presenter.troubles.sole.subject.fund_gap).to eq(200)
    end

    # THE OTHER DIRECTION, WHICH IS NOW THE DATE'S: the same bill anchored a month AHEAD of `today` is
    # a fund still saving, and saving is not trouble. Silence is the good state.
    it "leaves a bill whose date is still ahead out of the list", :aggregate_failures do
      income(2_000)
      utilities = holder("Utilities", priority: 1)
      rolling(utilities, amount: 600, anchor: Date.new(2026, 3, 2), every: 6)

      expect(presenter.troubles.map(&:kind)).to eq([])
      expect(presenter).not_to be_trouble
    end

    # MAIN'S OVERDRAFT IS THE HERO'S RED FIGURE, so the strip must not repeat it: printing the same
    # debt twice with two different sentences about what counts it is worse than printing it once.
    # (`free` is −$400 here too, so the :shortfall arm IS true — which is the point of asserting the
    # whole list rather than just the absence of :overdraft.)
    it "leaves main's own overdraft out of the list", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Overspend"), 400)

      expect(presenter.in_checking).to eq(-400)
      expect(presenter.troubles.map(&:kind)).to eq([:shortfall])
    end

    # SILENCE IS THE GOOD STATE (answers-first §5). $400 in against a $400 claim leaves free at
    # exactly zero, which is not negative, so nothing at all is true.
    it "asks nothing of a user whose claims fit", :aggregate_failures do
      income(400)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.free_to_spend).to eq(0)
      expect(presenter.troubles).to be_empty
      expect(presenter).not_to be_trouble
    end
  end

  # ── FREE BELOW ZERO — THE SIGNAL (computed-claims §4) ──────────────────────────────────────────
  describe "#uncovered_claims" do
    # ** THE GIVE-WAY WALK, AND THE SPLIT IS WHAT MAKES IT A WALK. ** PLANTED, every figure from §3.1:
    #   Rent      priority 1, $1,000 a period, nothing spent → claim $1,000.00
    #   Groceries priority 2,   $400 a period, nothing spent → claim   $400.00
    #   Fun       priority 3,   $200 a period, nothing spent → claim   $200.00
    #   Σ claims $1,600.00 against $1,340 of money → `unclaimed` −$260.00, so the shortfall is $260.
    #
    # REVERSE PRIORITY: Fun gives way first and gives its whole $200; $60 is left, so GROCERIES IS
    # SPLIT at $60 of its $400 and RENT — first in priority — is never reached.
    it "walks the claims in reverse priority until the shortfall is absorbed", :aggregate_failures do
      income(1_340)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)
      rate(holder("Fun", priority: 3), 200)

      expect(presenter.shortfall).to eq(260)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] })
        .to eq([["Fun", 200], ["Groceries", 60]])
      expect(presenter.uncovered_claims.map(&:whole?)).to eq([true, false])
    end

    # THE OTHER DIRECTION: nothing is uncovered when the claims fit, and the list is empty rather than
    # full of zeroes.
    it "is empty while free is not negative" do
      income(1_800)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)

      expect(presenter.uncovered_claims).to be_empty
    end

    # A CLAIM OF ZERO IS SKIPPED rather than listed as covered: a rate rule spent flat claims nothing,
    # and a row saying "$0.00 of it is uncovered" reports nothing. PLANTED: Fun's $200 rate is spent
    # flat, so its claim is `max(0, 200 − 200)` = $0.00 and Σ claims is $1,400. The $200 left checking
    # too, so total money is `1,340 − 200` = $1,140, `unclaimed` is −$260.00 and the shortfall is the
    # same **$260.00** as the example above — the walk passes over Fun and takes all of it out of
    # Groceries.
    it "passes over a rule that claims nothing", :aggregate_failures do
      income(1_340)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)
      fun = holder("Fun", priority: 3)
      rate(fun, 200)
      spend(fun, 200)

      expect(presenter.shortfall).to eq(260)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] }).to eq([["Groceries", 260]])
    end

    # ** THE WALK RUNS ON `free < 0` AND ON NOTHING ELSE (two-shapes §2). ** Its gate was
    # `#claims_outrun_the_money?`, because the capped `free` could go below zero with every claim
    # covered by money sitting outside checking — the walk ran there anyway and named claims the
    # savings cover, which is the strip asserting a cause it never established. There is one cause per
    # sign now, so `#short?` IS that predicate.
    #
    # THE SAME FIXTURE, RE-DERIVED: $800 of income, $1,000 walked over to Ally, one $500-a-period rule
    # with nothing spent. The pot is `800 − 1,000` = −$200.00 and Σ claims is $500.00, so `free` is
    # −$700.00 — and the rules really are $700 short OF CHECKING, whatever Ally holds. The list names
    # Groceries' whole $500 and the remainder names the $200 already spent past zero, which is the
    # money in Ally read from the other side.
    it "walks the claims wherever checking is short, whatever another account holds", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(800)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_000, date: today, kind: :transfer)
      rate(holder("Groceries", priority: 1), 500)

      expect(presenter.shortfall).to eq(700)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] }).to eq([["Groceries", 500]])
      expect(presenter.uncovered_remainder).to eq(200)
    end

    # ** THE SHORTFALL CAN OUTLAST THE CLAIMS, AND THE REMAINDER HAS TO BE NAMED (fix round 1 —
    # LOW-1). ** The walk runs out of claims and the list then sums to LESS than the headline, with
    # nothing on the screen saying where the difference went.
    #
    # PLANTED: $400 spent on an unbudgeted category with no income at all, so the pot and the total
    # are both −$400.00, beside one $500-a-period rule with nothing spent (claim **$500.00**).
    # `unclaimed = −400 − 500` = −$900.00 and `free = min(−400, −900)` is −$900.00. The walk takes
    # Groceries' whole $500 and stops; `900 − 500` = **$400.00** is past every claim there is — which
    # is the money already spent past zero.
    it "names what the shortfall is past every claim", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 400)
      rate(holder("Groceries", priority: 1), 500)

      expect(presenter.shortfall).to eq(900)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] }).to eq([["Groceries", 500]])
      expect(presenter.uncovered_remainder).to eq(400)
    end

    # THE OTHER DIRECTION: a shortfall the claims absorb leaves no remainder, and a sentence about
    # $0.00 past everything would be a line reporting nothing.
    it "has no remainder while the claims absorb the shortfall", :aggregate_failures do
      income(1_340)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)
      rate(holder("Fun", priority: 3), 200)

      expect(presenter.uncovered_remainder).to eq(0)
    end

    # ** A PRIORITY TIE IS BROKEN BY NAME, AND THE WALK REVERSES THAT (fix round 1 — LOW-2), AND THE
    # NEW KEY KEEPS IT (rules-own-the-budget spec §3). ** `#budgeted_categories` sorts on
    # `[priority, name]` — `Category.in_fill_order`'s own key, because priority alone is not a total
    # order — and `#give_way_order`'s second term is that list's index NEGATED. So at one priority
    # the LATER name still gives way FIRST; what changed is that the reversal is now a term in one
    # sort rather than a `.reverse` on a category walk, and the TYPE is asked before it.
    #
    # RE-DERIVED UNDER THE NEW KEY: both rules are `usage` (the column's default), so `type_rank` is
    # 1 for each and the tie falls straight through to the category term. `#budgeted_categories` is
    # `[Alpha, Zed]`, so the ranks are `0` and `−1` and Zed sorts first — the same order the old
    # `.reverse` produced, on the same fixture.
    #
    # PLANTED: two $300-a-period rules at priority 2 against $200 of income. Σ claims $600.00,
    # `unclaimed = 200 − 600` = −$400.00, `free = min(200, −400)` = −$400.00. Zed's whole $300 goes
    # first and Alpha is split at the remaining **$100.00**.
    it "gives way in reverse name order where two categories share a priority", :aggregate_failures do
      income(200)
      rate(holder("Alpha", priority: 2), 300)
      rate(holder("Zed", priority: 2), 300)

      expect(presenter.shortfall).to eq(400)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] })
        .to eq([["Zed", 300], ["Alpha", 100]])
    end
  end

  # ── ** THE TYPE DECIDES BEFORE PRIORITY DOES (rules-own-the-budget spec §3) ** ──────────────────
  #
  # `#give_way_order` is ONE sort over every claim line: `[Budget#type_rank, the category's place in
  # `#budgeted_categories` negated, Category.rule_order]`. It replaced a category-level walk
  # (`budgeted_categories.reverse.flat_map`), which could only rank whole categories — so a bill and
  # a restaurant fund sitting on one category gave way together, at whatever rank their category
  # held.
  #
  # EVERY FIXTURE BELOW PUTS THE TYPE AND THE PRIORITY IN OPPOSITION, deliberately: the choice rule
  # is on the LOWEST priority number (the most protected category under the old order) and the bill
  # on the highest. Under `budgeted_categories.reverse` the bill would have been eaten first and the
  # choice never reached, which is the exact inversion these examples are for.
  describe "#give_way_order" do
    # PLANTED, and every figure re-derived from §3.1:
    #   Fun       priority 1, CHOICE, $200 a period, nothing spent → claim   $200.00
    #   Groceries priority 2, USAGE,  $400 a period, nothing spent → claim   $400.00
    #   Rent      priority 3, BILL, $1,000 a period, nothing spent → claim $1,000.00
    #   Σ claims $1,600.00 against $1,340 of income → `unclaimed` −$260.00, so the shortfall is $260.
    #
    # CHOICE FIRST: Fun gives its whole $200; $60 is left, so GROCERIES IS SPLIT at $60 of its $400
    # and RENT — a bill — is never reached at all. Under the old reverse-priority walk this fixture
    # answered `[["Rent", 260]]`, which is the app naming the rent as the thing to go without.
    it "eats a choice whole, splits a usage and never reaches a bill", :aggregate_failures do
      income(1_340)
      rate(holder("Fun", priority: 1), 200, type: :choice)
      rate(holder("Groceries", priority: 2), 400, type: :usage)
      rate(holder("Rent", priority: 3), 1_000, type: :bill)

      expect(presenter.shortfall).to eq(260)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] })
        .to eq([["Fun", 200], ["Groceries", 60]])
      expect(presenter.uncovered_claims.map(&:whole?)).to eq([true, false])
    end

    # THE ORDER ITSELF, which is the produced interface and is asserted whole rather than through
    # the walk that consumes it: the walk stops when the shortfall is absorbed, so a list read only
    # through `#uncovered_claims` can never show what comes AFTER the split. Same three rules, no
    # shortfall at all.
    it "lists every line choice first and bill last, whatever the priorities say" do
      income(4_000)
      rate(holder("Fun", priority: 1), 200, type: :choice)
      rate(holder("Groceries", priority: 2), 400, type: :usage)
      rate(holder("Rent", priority: 3), 1_000, type: :bill)

      expect(presenter.give_way_order.map { |line| line.category.name }).to eq(["Fun", "Groceries", "Rent"])
    end

    # ** WITHIN A TYPE, PRIORITY STILL DECIDES, AND IT DECIDES THE SAME WAY IT ALWAYS HAS: the
    # category that would have been funded LAST goes without FIRST. ** Two CHOICE rules, so the
    # first term of the key is a tie and the second does all the work.
    #
    # PLANTED: Dining priority 1 and Hobbies priority 3, $300 a period each, against $200 of income.
    # Σ claims $600.00, `unclaimed = 200 − 600` = −$400.00, `free = min(200, −400)` = −$400.00.
    # `#budgeted_categories` is `[Dining, Hobbies]`, so the ranks are `0` and `−1`: Hobbies gives its
    # whole $300 and Dining is split at the remaining **$100.00**.
    it "gives way in reverse priority order inside one type", :aggregate_failures do
      income(200)
      rate(holder("Dining", priority: 1), 300, type: :choice)
      rate(holder("Hobbies", priority: 3), 300, type: :choice)

      expect(presenter.shortfall).to eq(400)
      expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] })
        .to eq([["Hobbies", 300], ["Dining", 100]])
    end

    # ** THE OPEN QUESTION §3 CLOSES: TWO RULES OF DIFFERENT TYPES ON ONE CATEGORY. ** The old walk
    # could not answer it — a category was ranked once and all of its rules gave way together — and
    # the honest answer is that the type decides here exactly as it decides between categories.
    #
    # PLANTED: Household, priority 1, funded. Its ITEM-LESS rule is a $300-a-period CHOICE and an
    # ITEM-BACKED one is a $500-a-period BILL (a category may hold only one item-less rule). Both
    # are rate rules with nothing spent, so Σ claims is $800.00 against $700 of income: `unclaimed`
    # −$100.00 and the shortfall is $100. The CHOICE rule is split at $100 and the bill on the very
    # same heading is never reached.
    it "ranks two rules on one category by their own types", :aggregate_failures do
      household = holder("Household", priority: 1)
      income(700)
      rate(household, 300, type: :choice)
      rate(household, 500, type: :bill, item: lane(household, "Insurance"))

      expect(presenter.shortfall).to eq(100)
      expect(presenter.uncovered_claims.map { |u| [u.line.rule.rule_type, u.amount] })
        .to eq([["choice", 100]])
    end
  end

  describe "#per_day_pace" do
    # `shortfall ÷ days left`, and the days come from `Progress#days_left` — `User#period_containing`,
    # the one reader that owns this calendar. PLANTED: $260 short on Feb 6, day 1 of the Feb 6–19
    # period, so 13 days remain and `260 ÷ 13` = **$20.00**.
    it "spreads the shortfall over the days that are left" do
      income(1_340)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)
      rate(holder("Fun", priority: 3), 200)

      expect(presenter.per_day_pace).to eq(20)
    end

    # ** THE CLOSING DAY, WHERE `days_left` IS ZERO. ** The floor at one is the day the user is
    # standing in rather than a guard against a bad number — dividing by zero would raise on the one
    # afternoon the sentence matters most. Feb 19 is day 14 of 14, so the whole $260 lands on today.
    it "puts the whole shortfall on today when the period closes today" do
      income(1_340)
      rate(holder("Rent", priority: 1), 1_000)
      rate(holder("Groceries", priority: 2), 400)
      rate(holder("Fun", priority: 3), 200)

      expect(described_class.new(user: user, today: Date.new(2026, 2, 19)).per_day_pace).to eq(260)
    end

    it "is nil while free is not negative" do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.per_day_pace).to be_nil
    end

    # NO DECLARED PERIOD, NO PACE — there is no "rest of the period" to spread a shortfall over, and
    # inventing a calendar month would state a boundary nobody set.
    it "is nil before a period is declared", :aggregate_failures do
      user.update!(period_cadence: nil, period_anchor_date: nil)
      income(150)
      rate(holder("Groceries", priority: 1), 400)
      fresh = described_class.new(user: user, today: today)

      expect(fresh.shortfall).to eq(250)
      expect(fresh.per_day_pace).to be_nil
    end
  end

  # ── THE ACCOUNTS LINE (answers-first §6) ──────────────────────────────────────────────────────
  describe "#other_accounts" do
    # MAIN IS OUT OF THE FIGURE because its balance IS the hero's "In Checking" number; an onboarding
    # account is out because its card renders top-level, and a figure in the line for a card sitting
    # above it reads as two accounts.
    it "totals the finished accounts that are not main", :aggregate_failures do
      create(:category, :expense, user: user, name: "Opening Balance")
      income(1_000)
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 400, date: today, kind: :transfer)
      create(:pool, :account, user: user, name: "Fresh")

      expect(presenter.other_accounts).to eq([ally])
      expect(presenter.other_accounts_total).to eq(400)
      expect(presenter.onboarding_accounts.map(&:name)).to eq(["Fresh"])
      expect(presenter.collapsed_accounts).to eq([ally, checking])
    end
  end

  describe "#structurally_underwater?" do
    it "is true when the rules need more than typical income" do
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).to be_structurally_underwater
    end

    it "is false when they fit" do
      rate(holder("Rent", priority: 1), 500)

      expect(presenter).not_to be_structurally_underwater
    end

    # The boundary the `>` sits on. Rules that consume the declared income exactly are not a
    # structural problem, so this must not fire.
    it "is false when the rules land exactly on typical income", :aggregate_failures do
      rate(holder("Rent", priority: 1), 2_400)

      expect(presenter.total_claims).to eq(user.typical_income)
      expect(presenter).not_to be_structurally_underwater
    end

    it "is false when typical income is unset" do
      user.update!(typical_income: nil)
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).not_to be_structurally_underwater
    end

    # THE OTHER HALF OF THE DECLARATION. Income with a blank cadence is reachable — the Budget page's
    # form offers "Not set" and clearing the period deliberately keeps the income — and in that state
    # `Budget.steady_need` falls back to treating a period as a calendar month. A per-rule normaliser
    # may fall back; a VERDICT may not.
    it "is false when income is declared but no cadence is", :aggregate_failures do
      rate(holder("Rent", priority: 1), 3_000)

      expect(presenter).to be_structurally_underwater

      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(described_class.new(user: user, today: today)).not_to be_structurally_underwater
    end

    # THE MEMO, asserted by counting the sum rather than by trusting the spelling. `false` is the case
    # that needs the assertion: a `||=` memo re-runs its body every time the answer is falsey, so the
    # memo would be silently absent for exactly the population it was written for.
    it "computes the sum once for a budget that does not fit" do
      rate(holder("Rent", priority: 1), 3_000)
      allow(Budget).to receive(:steady_need).and_call_original

      3.times { presenter.structurally_underwater? }

      expect(Budget).to have_received(:steady_need).once
    end

    it "computes the sum once for a budget that does fit" do
      rate(holder("Rent", priority: 1), 500)
      allow(Budget).to receive(:steady_need).and_call_original

      3.times { presenter.structurally_underwater? }

      expect(Budget).to have_received(:steady_need).once
    end

    # ** THE STRUCTURAL QUESTION IS NOT Σ CLAIMS, AND THE DIVERGENCE SURVIVED THE CHANGE OF READERS. **
    # A $5,200 annual premium falling due inside the current period accrues its whole face value now
    # (§3.2's catch-up floors `periods_left` at 1), so Σ claims clears the declared $2,400 twice over
    # while the rules cost $200 a period. A verdict read off this period's claims would tell that user
    # their budget does not fit.
    it "is false in a catch-up period whose rules still fit the income", :aggregate_failures do
      annual(holder("Car Insurance", priority: 1), amount: 5_200, due: today + 3.days)

      expect(presenter.total_claims).to be > user.typical_income
      expect(Budget.steady_need(user, today: today)).to eq(200)
      expect(presenter).not_to be_structurally_underwater
    end

    # The other half of the divergence, and the dangerous one: a rate rule spent flat claims NOTHING
    # this period, so a verdict read off Σ claims would read $0 against $2,400 and stay silent on a
    # budget that cannot be made to work at any spending.
    it "is true on a period whose claims have been spent flat", :aggregate_failures do
      rent = holder("Rent", priority: 1)
      rate(rent, 3_000)
      spend(rent, 3_000)

      expect(presenter.total_claims).to eq(0)
      expect(presenter).to be_structurally_underwater
    end
  end
end
