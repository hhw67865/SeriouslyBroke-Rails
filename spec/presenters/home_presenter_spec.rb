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

  # A GOAL IS A HOLDER WITH A TARGET, and under computed claims it is also a RULE with one (§3.2):
  # every claim comes from a rule, so a goal fed only by hand is a rule whose amount is zero.
  def savings_goal(name, priority:, target: 1_200)
    holder(name, priority: priority).tap { |category| category.update!(target_amount: target) }
  end

  # THE RULE A HAND-FED GOAL IS (§3.2's "no rate" spelled as a zero amount), with its birthday planted
  # for the reason `#bill` states: a rule younger than `today` walks no periods and holds nothing,
  # however many set-asides are dated inside them.
  def goal_rule(category, created_at: Time.zone.local(2025, 1, 1))
    create(:budget, :per_period_rate, category: category, amount: 0, created_at: created_at)
  end

  # A flat per-period rule: the catch-all shape, and the one whose claim is exactly `rate − spent`.
  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount)
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
      expect(presenter.period_rows.map { |row| row.category.name }).to eq(["Groceries", "Coffee"])
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
      expect(presenter).not_to be_free_cap_bound
    end

    # ARCHETYPE 2, FIRST DIRECTION: the `min` chooses the SUBTRACTION. PLANTED — $2,000 in, one
    # $400-a-period rule with nothing spent, so `claim = max(0, 400 − 0)` = $400.00 (§3.1) and
    # `free = min(2,000, 2,000 − 400)` = **$1,600.00**. The pot is nowhere near binding.
    it "is the money less the claims when it is all in checking", :aggregate_failures do
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.in_checking).to eq(2_000)
      expect(presenter.total_claims).to eq(400)
      expect(presenter.free_to_spend).to eq(1_600)
      expect(presenter).not_to be_free_cap_bound
    end

    # ARCHETYPE 2, SECOND DIRECTION: the `min` chooses the POT, which is the ruled cap (§2) — money
    # you would have to move out of savings first is not free in the moment. THE SAME FIXTURE with
    # $1,500 walked over to Ally: an account movement claims nothing, so `total_money − Σ claims` is
    # still $1,600 and only the cap brings the answer down to the $500 the pot holds. A reader that
    # had quietly dropped the `min` would still read $1,600 here.
    it "is capped at the pot when the unclaimed money is parked elsewhere", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(2_000)
      rate(holder("Groceries", priority: 1), 400)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(500)
      expect(presenter.total_claims).to eq(400)
      expect(presenter.free_to_spend).to eq(500)
      expect(presenter).to be_free_cap_bound
    end

    # ARCHETYPE 3: free below zero, NEVER clamped (§4: a signal, not a refusal). $150 in against a
    # $400 claim — the rules ask for $250 more than exists, and the card has to say so.
    it "states the gap rather than reporting nothing left", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)

      expect(presenter.free_to_spend).to eq(-250)
      expect(presenter).not_to be_free_cap_bound
    end

    # THE PURE OVERSPEND. No rules at all, so nothing is claimed, while $100 of spending has taken the
    # pot below zero. `free` is simply -$100.00 — the honest sentence, with no branch to get wrong.
    it "is negative for a period whose spending has taken the pot under", :aggregate_failures do
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 100)

      expect(presenter.total_claims).to eq(0)
      expect(presenter.free_to_spend).to eq(-100)
    end

    # ARCHETYPE 4: the physical overdraft, with a claim still standing beside it. PLANTED — $1,000 in,
    # a $1,000-a-period rule, $600 spent on it: `claim = max(0, 1,000 − 600)` = **$400.00**, total
    # money is `1,000 − 600` = **$400.00**, so `unclaimed` is $0.00 and `free = min(400, 0)` = $0.00.
    # Spend $200 more and both go under together, which is the next example's job.
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

  # ** WHICH KIND OF NEGATIVE. ** `#free_to_spend` goes below zero for two unrelated reasons and the
  # card was telling both of them the same story. The four examples below are the combinations that
  # exist, and the third is what makes this a separate predicate rather than a synonym for
  # `#free_cap_bound?`.
  describe "#claims_outrun_the_money?" do
    # THE MEASURED FIXTURE. $1,000 of income, $1,200 walked over to a savings account, and NOT ONE
    # RULE — total money is still $1,000 and nothing is claimed, so `unclaimed` is +$1,000 while the
    # pot is −$200 and the CAP is what took free under. Nothing about this user's budget is wrong.
    it "is false when the money is simply in another account", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_200, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(-200)
      expect(presenter.total_claims).to eq(0)
      expect(presenter.free_to_spend).to eq(-200)
      expect(presenter).to be_free_cap_bound
      expect(presenter).not_to be_claims_outrun_the_money
    end

    # THE OTHER DIRECTION: $150 in, $300 spent with no rule to claim it, and a $400 rule still
    # claiming. Total money is `150 − 300` = −$150 and Σ claims is $400, so `unclaimed` is −$550 and
    # `free = min(−150, −550)` is −$550 — genuinely nothing anywhere, and the cap is NOT what did it.
    it "is true when every account together is short of the claims", :aggregate_failures do
      income(150)
      rate(holder("Groceries", priority: 1), 400)
      spend(create(:category, :expense, user: user, name: "Unbudgeted"), 300)

      expect(presenter.in_checking).to eq(-150)
      expect(presenter.free_to_spend).to eq(-550)
      expect(presenter).not_to be_free_cap_bound
      expect(presenter).to be_claims_outrun_the_money
    end

    # ** THE COMBINATION THAT FORBIDS SPELLING THIS AS `#free_cap_bound?`. ** $1,000 in, $1,500 moved
    # to savings and a $1,100 rule still claiming: total money $1,000, `unclaimed` −$100, pot −$500.
    # The cap binds (−500 < −100) AND the claims outrun the money. Both predicates are true, they are
    # answering different questions, and a card that used the cap as a proxy for the cause would tell
    # this user their money is merely in the wrong account.
    it "is true even where the cap binds, because they are different questions", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(1_000)
      rate(holder("Groceries", priority: 1), 1_100)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

      expect(presenter.in_checking).to eq(-500)
      expect(presenter.total_claims).to eq(1_100)
      expect(presenter).to be_free_cap_bound
      expect(presenter).to be_claims_outrun_the_money
    end

    it "is false for a fresh user, whose rules claim nothing at all" do
      expect(presenter).not_to be_claims_outrun_the_money
    end
  end

  describe "#free_cap_bound?" do
    # THE BOUNDARY THE `<` SITS ON. Money exactly equal to what the pot holds is not "parked somewhere
    # else", so the subline must not fire: $1,000 in checking against $1,000 unclaimed is one pile,
    # and the card would be inventing a second.
    it "is false when the two sides of the min are equal", :aggregate_failures do
      income(1_000)

      expect(presenter.free_to_spend).to eq(1_000)
      expect(presenter).not_to be_free_cap_bound
    end
  end

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
      # ** THE SINGLE-ACCOUNT CAP CORNER IS NOW STRUCTURALLY IMPOSSIBLE, and this is what says so. **
      # The answers-first review's M-1 fixture lived in the identity's THIRD term (a category
      # overdrawn by $200 made the root exceed the pot with no second account in existence). A claim
      # can never be negative, so with one account `unclaimed − pot = −Σ claims ≤ 0` and the cap
      # cannot bind at all. PLANTED at the same shape: $1,000 in, a $900 rate rule, $1,100 spent —
      # `claim = max(0, 900 − 1,100)` = $0.00, pot and total money both −$100.
      it "is false where a category was overspent on a single account", :aggregate_failures do
        groceries = holder("Groceries", priority: 1)
        income(1_000)
        rate(groceries, 900)
        spend(groceries, 1_100)

        expect([presenter.in_checking, presenter.total_claims]).to eq([-100, 0])
        expect(presenter.free_to_spend).to eq(-100)
        expect(presenter).not_to be_free_cap_bound
        expect(presenter).to be_claims_outrun_the_money
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
      # THE PURE OVERSPEND: no rule claims anything and the pot is simply below zero.
      # `#claims_outrun_the_money?` is TRUE here — the branch was always right, and this is the
      # predicate that keeps its sentence from naming something that does not exist.
      it "is false for an account that has only been spent past zero", :aggregate_failures do
        spend(create(:category, :expense, user: user, name: "Unbudgeted"), 100)

        expect(presenter.free_to_spend).to eq(-100)
        expect(presenter).to be_claims_outrun_the_money
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

      # THE ACCRUING SIDE, so the predicate is not a fact about rate rules alone. PLANTED: a $1,200
      # goal fed by a single dated adjustment of $400 (§3.3) on a zero-amount target rule — its period
      # accrues `min(rate 0, gap 1,200)` = $0 plus the $400 delta, capped at the target and with
      # nothing spent, so `built_up` and the claim are **$400.00**.
      it "is true for a fund built up out of set-asides alone", :aggregate_failures do
        goal = savings_goal("Vacation", priority: 1, target: 1_200)
        set_aside(goal_rule(goal), 400)

        expect(presenter.total_claims).to eq(400)
        expect(presenter).to be_anything_claimed
      end
    end

    describe "#rest_in_checking?" do
      it "is true when the pot holds more than the unclaimed money", :aggregate_failures do
        income(2_000)
        rate(holder("Groceries", priority: 1), 400)

        expect(presenter.free_to_spend).to eq(1_600)
        expect(presenter).to be_rest_in_checking
        expect(presenter).to be_anything_claimed
      end

      # ** IT SAYS A REST EXISTS AND NOTHING ABOUT WHAT IT IS. ** `pot − free` is
      # `Σ claims − Σ other accounts`, so with nothing claimed a positive rest is an OTHER ACCOUNT IN
      # THE RED: $1,000 of income and $200 walked out of an Ally that is $200 overdrawn leaves the pot
      # at $1,200 against $1,000 of total money. The arm asks BOTH predicates, and this is the fixture
      # that separates them.
      it "is true for a rest that nothing claims", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(1_000)
        create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: today, kind: :transfer)

        expect([presenter.in_checking, presenter.free_to_spend]).to eq([1_200, 1_000])
        expect(presenter).to be_rest_in_checking
        expect(presenter).not_to be_anything_claimed
      end

      # ** THE FRESH SIGNUP'S IDENTITY CORNER. ** Money in, nothing claimed, so free IS the pot to the
      # cent and there is no rest for a sentence to be about. NOT the negation of `#free_cap_bound?` —
      # both are false here, and that is the state that needs its own words.
      it "is false when free is the whole pot", :aggregate_failures do
        income(1_000)

        expect(presenter.free_to_spend).to eq(presenter.in_checking)
        expect(presenter).not_to be_free_cap_bound
        expect(presenter).not_to be_rest_in_checking
      end

      # The cap-bound direction: `pot − free` is zero in every one of these states, so "the rest" was
      # $0.00 wherever the card appended "more is parked in other accounts" to it.
      it "is false wherever the cap bound", :aggregate_failures do
        ally = create(:pool, :account, user: user, name: "Ally")
        income(2_000)
        rate(holder("Groceries", priority: 1), 400)
        create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_500, date: today, kind: :transfer)

        expect(presenter).to be_free_cap_bound
        expect(presenter).not_to be_rest_in_checking
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

    # EVERYTHING A RENDERED HOME ASKS FOR, in the order the page asks it — the hero's own readers,
    # then the three panels below it. Split in two because one method asking twelve questions of one
    # object is past rubocop's ABC limit, not because the halves mean anything separately.
    def read_the_screen
      read_the_hero
      read_screen_for(presenter)
    end

    def read_the_hero
      presenter.free_cap_bound?
      presenter.claims_outrun_the_money?
      presenter.rest_in_checking?
      presenter.money_parked_elsewhere?
      presenter.anything_claimed?
      presenter.period_progress
    end

    # ONE CATEGORY, `count` PER-PERIOD RATE RULES: the first names no item (the catch-all lane) and
    # the rest name one each (the item lane), so BOTH of the claim ledger's two spending statements
    # run at every size and the comparison is not measuring a lane appearing.
    #
    # PER-PERIOD AND NOT DATED, deliberately: `Budget.steady_need` — which the :structural trouble
    # reads — builds a `BudgetCalculator` per ONE-OFF rule and runs a SUM inside it, which is a
    # per-rule cost this task did not introduce and cannot fix from here. A per-period rule's
    # `#steady_ask` is its own amount, so the pin measures what it is about.
    def rules_on_one_category(count)
      category = holder("Pet Care", priority: 1)
      rate(category, 400)
      (count - 1).times { |n| create(:budget, :per_period_rate, category: category, amount: 50, item: lane(category, "Lane #{n}")) }
      category
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
    end

    def read_screen_for(other)
      other.in_checking
      other.free_to_spend
      other.period_rows
      other.unbudgeted_rows
      other.troubles
      other.uncovered_claims
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

    # NINETEEN, AND EACH ONE IS NAMED — a bare number is a pin nobody can maintain:
    #
    #    1-2. `AccountLedger#entry_side`'s income and expense SUMs — the pot's own term, memoised in
    #         that class as of this task (it ran three times over before, once for the hero's figure,
    #         once inside `#total_money` and once for the overdraft walk).
    #    3-4. its two grouped movement sums, in and out.
    #      5. `ClaimLedger#total_money`'s fetch of the user's accounts.
    #      6. `ClaimLedger#rules` — every rule the user owns …
    #    7-8. … and its `:item, category: :user` preload, one statement each.
    #      9. the claim ledger's CATCH-ALL spending lane. (The ITEM lane is absent here: no rule on
    #         this fixture names one, and the ledger does not query for an empty id list.)
    #     10. its adjustment lane.
    #     11. `#accounts` — the user's accounts by name, for the accounts line and the overdraft walk.
    #     12. `#categories` — the holders in fill order …
    #     13. … and its `:budgets` preload.
    #     14. `#holder_spending_this_period` — ONE grouped sum for every row on the screen.
    #     15. `#unbudgeted_spending_this_period` — the same expression read for its NULL answer.
    #     16. `#unbudgeted_rows`' name-ordered fetch of the categories those ids name.
    #  17-19. `Budget.steady_need` and its own preload, for the :structural trouble.
    it "costs nineteen statements for a whole render" do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)
      spend(create(:category, :expense, user: user, name: "Subscriptions"), 32)

      expect(count_statements { read_the_screen }).to eq(19)
    end

    # THE UNBUDGETED FETCH IS CONDITIONAL, and this is what says so: the same screen with nothing
    # unbudgeted spent on it costs one fewer, because `#unbudgeted_rows` returns without querying for
    # records nothing named.
    it "costs one fewer when nothing unbudgeted was spent this period" do
      income(2_000)
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310)

      expect(count_statements { read_the_screen }).to eq(18)
    end
  end

  # ── "THIS PERIOD" (answers-first §4, computed-claims §3.4) ────────────────────────────────────
  #
  # The bars themselves are pinned in `spec/system/home/this_period_spec.rb`, on the screen. What is
  # here is what a browser cannot reach cheaply: the WINDOW both directions, the partition between a
  # budgeted row and an unbudgeted one, the per-rule lines, and the sort key.
  describe "#period_rows" do
    # THE WINDOW, BOTH DIRECTIONS, ON ONE CATEGORY. The period containing Feb 6 on a biweekly cadence
    # anchored Feb 6 is Feb 6–19, so the Feb 10 receipt is inside it and the Feb 2 one is not — and a
    # rate claim counts THIS period alone (§3.1), which is why the line reads $310 and not $360.
    it "counts the spending inside this period and no other", :aggregate_failures do
      groceries = holder("Groceries", priority: 1)
      rate(groceries, 400)
      spend(groceries, 310, on: Date.new(2026, 2, 10))
      spend(groceries, 50, on: Date.new(2026, 2, 2))

      line = presenter.period_rows.sole.lines.sole

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
      line = presenter.period_rows.sole.lines.sole

      expect(line).not_to be_rate
      expect(line.target).to eq(600)
      expect(line.next_due_on).to eq(Date.new(2026, 3, 1))
    end

    # A GOAL MEASURES AGAINST ITS TARGET (§3.4), and #filled is what it has BUILT UP rather than its
    # spending — which is what keeps the row from reading as money to spend. PLANTED: a $2,400 goal on
    # a zero-amount rule with a single $424 set-aside (§3.3), so `built_up` is $424.00 and the bar is
    # `round(424 / 2,400 × 100)` = **18%**.
    it "measures a goal against its target and fills the bar with what it has built up", :aggregate_failures do
      goal = savings_goal("Vacation", priority: 1, target: 2_400)
      set_aside(goal_rule(goal), 424)
      line = presenter.period_rows.sole.lines.sole

      expect(line).not_to be_rate
      expect(line.target).to eq(2_400)
      expect(line.filled).to eq(424)
      expect(line.percent).to eq(18)
    end

    # ** A ROW PER CATEGORY, A LINE PER RULE — THE RULING (see HomePresenter::PeriodRow). ** A rate
    # rule beside an item-backed bill cannot honestly print one figure: `spent of rate` and `built up
    # of target` are denominated in different things and summing them would state a number that is
    # true of neither. PLANTED: $400 rate with $150 spent on an UN-ruled item → claim $250; a $600
    # bill on the Vet item, accruing since Jan 2025 against a Feb 14 2026 due date. The due date sits
    # INSIDE the current period, so §3.2's `periods_left` is 1 there and the catch-up formula closes
    # the gap exactly — `built_up` is the whole **$600.00**. The two lanes partition (§3.1), which is
    # why the rate rule's spending is $150 and not $150 plus whatever the bill's item took.
    it "gives a category with two rules one line each", :aggregate_failures do
      pet_care = holder("Pet Care", priority: 1)
      rate(pet_care, 400)
      bill(pet_care, amount: 600, due: Date.new(2026, 2, 14), item: lane(pet_care, "Vet"))
      spend(pet_care, 150)

      lines = presenter.period_rows.sole.lines

      expect(lines.map(&:shape)).to eq([:rate, :dated])
      expect(lines.first.spent).to eq(150)
      expect(lines.first.claim).to eq(250)
      expect(lines.second.built_up).to eq(600)
      expect(presenter.total_claims).to eq(850)
    end

    # TROUBLE FIRST, THEN PRIORITY. Three categories in priority order 1-2-3 with the LAST in trouble:
    # both halves are asserted at once, because either alone passes against a list that was simply
    # reversed. PLANTED: $80 spent against a $50 rate is over by $30 (§3.1).
    it "sorts trouble first and keeps priority order behind it" do
      rate(holder("Rent", priority: 1), 400)
      rate(holder("Groceries", priority: 2), 400)
      dining = holder("Dining Out", priority: 3)
      rate(dining, 50)
      spend(dining, 80)

      expect(presenter.period_rows.map { |row| row.category.name }).to eq(["Dining Out", "Rent", "Groceries"])
    end

    # A HOLDER WITH NO RULE STATES ITS SPENDING AND NOTHING ELSE, and one with neither is absent —
    # `spent $0.00` under a name is a row that reports nothing.
    it "keeps a rule-less holder only while it has spending", :aggregate_failures do
      spend(holder("Car Repairs", priority: 1), 45)
      holder("Someday Fund", priority: 2)

      rows = presenter.period_rows

      expect(rows.map { |row| row.category.name }).to eq(["Car Repairs"])
      expect(rows.sole.lines).to be_empty
      expect(rows.sole.spent).to eq(45)
    end
  end

  describe "#unbudgeted_rows" do
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
      expect(presenter.period_rows.sole.lines.sole.spent).to eq(30)
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

    # ** NOTHING IS UNCOVERED WHEN THE MONEY IS SIMPLY IN THE WRONG ACCOUNT (fix round 1 — HIGH-1). **
    # `free < 0` has two causes and only ONE of them is a claim going unmet: where the CAP bound on a
    # negative pot, every claim is covered by money the user has — it is just not in checking. The walk
    # ran on `#shortfall` regardless and named claims the savings cover, which is the strip asserting a
    # cause it never established.
    #
    # PLANTED: $800 of income, $1,000 walked over to Ally, one $500-a-period rule with nothing spent.
    # Σ claims $500.00; total money is still $800, so `unclaimed = 800 − 500` = **$300.00** — the
    # claims do NOT outrun the money — while the pot is `800 − 1,000` = −$200.00 and
    # `free = min(−200, 300)` is −$200.00. The shortfall is real and the list is empty.
    it "names nothing when the money is in another account rather than short", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income(800)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_000, date: today, kind: :transfer)
      rate(holder("Groceries", priority: 1), 500)

      expect(presenter.shortfall).to eq(200)
      expect(presenter).not_to be_claims_outrun_the_money
      expect(presenter.uncovered_claims).to be_empty
      expect(presenter.uncovered_remainder).to eq(0)
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

    # ** A PRIORITY TIE IS BROKEN BY NAME, AND THE WALK REVERSES THAT (fix round 1 — LOW-2). **
    # `#budgeted_categories` sorts on `[priority, name]` — `Category.in_fill_order`'s own key, because
    # priority alone is not a total order — and the give-way walk reads it BACKWARDS. So at one
    # priority the LATER name gives way FIRST, which is what this pins: the order is a fact about the
    # screen rather than whatever the database returned this morning.
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
