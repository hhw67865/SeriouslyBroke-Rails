# frozen_string_literal: true

require "rails_helper"

# THE SAVINGS STRIP ON THE ALL TAB (plan 3, task 5), ABOUT CATEGORIES (two-ledger spec §3, Task 7),
# AND NOW ABOUT CLAIMS (computed-claims spec §3).
#
# ** THE FIXTURES ARE THE MODEL CHANGE, TWICE OVER. ** They planted savings POOLS funded by
# `AccountMovement`s; then savings CATEGORIES funded by `Allocation`s; and nothing moves at all now
# (§5). A category's money is `Σ its rules' claims`, so every goal below is planted as a RULE that
# accrues toward the category's target, and the figures are re-derived from §3.2's walk rather than
# carried:
#
#   built_up(P) = clamp( min(built_up_before + planned(P) + Σ adj(P), target) − spent(P), 0, target )
#   planned(P)  = the rule's own per-period rate, capped by what is still missing
#
# ** AND THE POPULATION IS THE OTHER HALF OF THE CONVERSION. ** The strip selected `Category
# #savings?` — holder, target, and NO RULE — and that third clause inverted under §3.3: every claim
# comes from a rule, so a `savings?` category claimed exactly $0.00, a goal with a rule feeding it
# was excluded for having the rule that put the money there, and `DropTheDistribution` (§7) mints
# that rule for every goal in a real database that lacked one. **The strip rendered nothing at all on
# migrated data.**
#
# ** THE CLASSIFIER IS `Budget.saving_toward_a_date` (two-shapes spec §2): an item-less rule with an
# anchor and NO interval. ** It has moved twice — a FIGURE on the CATEGORY, then the rule whose
# unspent money carried over — and "which money is being saved" is answered by the SHAPE either way.
# What the date adds is the one clause neither predecessor could draw: a rule that REPEATS is a
# recurring bill rather than something being saved toward, and it accrues by exactly the same walk.
# The population is pinned in five directions below, because a band that silently stops appearing is
# indistinguishable from one that broke.
#
# ── DELETED (computed-claims §3):
#
#   * "shows 'negative' badge when spending exceeds what was moved in" — §3.1 and §3.2 both clamp a
#     claim at zero, so no row here can carry a negative figure and the card's red "negative" badge
#     was a branch nothing could reach. The view's own header carries the argument; the state it was
#     really about — spending past what a rule had — is `ClaimCalculator#over?`, which Home's rows
#     and trouble strip report and which a progress-toward-a-target strip has no business
#     re-deriving.
#   * "pool balance reflects selected month" (the describe's premise, not its examples) — the strip
#     was bounded at `period_range.end`, and a claim has no such bound. `Dashboard::OverviewPresenter
#     #as_of` carries the whole ruling; what survives of the premise is that the figure is asked at
#     `min(the selected range's end, today)`, which for the default view is simply today.
#
# THE LINKS POINT AT THE CATEGORY, because the pool page is deleted and the category's own page is
# where a goal's figure, target and history all live now.
RSpec.describe "Dashboard Index - Savings strip", type: :system do
  # ** A DECLARED BIWEEKLY PERIOD, ANCHORED TODAY, AND IT IS NOT DECORATION. ** A claim is a walk
  # over periods, so a user with no cadence at all falls back to the calendar month and the walk's
  # arithmetic changes with the day of the month the suite runs on. Anchored on today, every rule
  # below is born as its first period opens and walks exactly ONE of them, which is what makes the
  # literals here readable.
  let!(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 4_000)
  end
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST for the `:account` trait's `after(:create)`
  # to nominate a main account. Nothing on the strip reads it.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  before { sign_in user, scope: :user }

  # A GOAL WITH SOMETHING IN IT: an expense category with a target, holding money from a year back,
  # and a per-period rule accruing toward the figure. `accrues` is capped by what is still missing
  # (§3.2's `planned_for`), so one walked period leaves `min(accrues, target)` built up.
  #
  # THE RULE IS BORN AS THE PERIOD OPENS and the category was funded a year back, so
  # `ClaimCalculator#accrual_start` is `max(funded_since, the rule's birthday)` = today, and the walk
  # visits exactly one period.
  # ** A GOAL IS A ONE-OFF DATED RULE WHOSE AMOUNT IS ITS TARGET (two-shapes spec §2 row 5), AND THE
  # HORIZON REPLACES THE RATE. ** The helper takes the same `accrues:` and DERIVES the day: this
  # file's grid is biweekly anchored today, so `target ÷ accrues` fortnights out leaves exactly that
  # many boundaries and §3.2's catch-up asks `accrues` in each — every literal below is unchanged.
  def goal(name, target, accrues:)
    category = create(:category, :expense, user: user, name: name, funded_since: 1.year.ago.to_date)
    create(
      :budget,
      category: category,
      amount: target,
      basis: :monthly,
      interval_months: nil,
      anchor_date: Date.current + ((14 * (target / accrues)) - 1).days
    )
    category
  end

  def spend(category, amount, on: Date.current)
    item = category.items.find_by(name: "Spending") || create(:item, category: category, name: "Spending")
    create(:entry, item: item, amount: amount, date: on)
  end

  def card(category) = find("[data-savings-strip] a[href='#{category_path(category)}']")

  # ** THE POPULATION, IN FOUR DIRECTIONS. ** Two in and two out, because the classifier has exactly
  # two clauses and a band that renders the wrong set is the defect this conversion was for.
  describe "which categories the strip holds", :aggregate_failures do
    # ** THE FIX, STATED AS A FIGURE. ** Under the deleted `#savings?` this category was excluded for
    # carrying the rule that put its money there, and since every claim comes from a rule that
    # excluded every goal with anything in it — the strip rendered nothing at all.
    it "holds a goal a rule feeds, which is every goal with money in it" do
      vacation = goal("Vacation Fund", 5_000, accrues: 1_000)

      visit reports_path

      expect(vacation.claim).to eq(BigDecimal("1000"))
      within(card(vacation)) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00")
        expect(page).to have_content("of $5,000.00")
      end
    end

    # ** THE "fund fed only by hand" EXAMPLE IS DELETED WITH THE SHAPE (two-shapes §7). ** It planted
    # a capped rule with an amount of ZERO — "no rate", the one shape `Budget` permitted a zero on —
    # and asserted the card was there claiming a truthful $0.00. Every rule has a positive amount now
    # and a goal accrues its first share the period it is written in, so the state cannot be reached
    # from a rule alone. What it was really pinning — a card on the strip for a fund barely started —
    # is the "barely started" arm below, where a distant date makes the first share nearly nothing.
    it "holds a goal whose date is far enough out that it has barely started", :aggregate_failures do
      someday = goal("Someday", 5_000, accrues: 5)

      visit reports_path

      expect(someday.claim).to eq(5)
      within(card(someday)) do
        expect(page).to have_content("$5.00")
        expect(page).to have_content("of $5,000.00")
      end
    end

    # ** A RULE THAT REPEATS IS A RECURRING BILL AND HAS NO CARD (two-shapes spec §2). ** It accrues
    # by exactly the same walk as a goal — the same catch-up share against the same kind of date —
    # and it is not savings: the water rates every six months are a bill that comes round. This is
    # the one clause `Budget.saving_toward_a_date` draws that neither predecessor could, because a
    # rule whose money merely carried over had no date to repeat on.
    #
    # ** IT REPLACES "holds a fund that names no figure" (§7), ** which planted the uncapped fund and
    # asserted a card with a built-up and NO "of": there was nothing for a track to be a fraction of.
    # Every accruing rule names a figure now.
    # FOUR FORTNIGHTS OUT, the same horizon `#goal` derives — so the only difference between this
    # rule and a goal is the interval, which is the clause under test.
    def repeating_bill(name, amount)
      category = create(:category, :expense, user: user, name: name, funded_since: 1.year.ago.to_date)
      create(
        :budget,
        category: category,
        amount: amount,
        basis: :monthly,
        interval_months: 6,
        anchor_date: Date.current + 55.days
      )
    end

    it "leaves out a category whose only dated rule repeats" do
      repeating_bill("Water", 1_000)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end

    # ** THE DIRECTION THE OLD CLASSIFIER GOT WRONG. ** A rule that RESETS every period is an
    # envelope, and it is here whatever else is true of its category. The example planted a figure on
    # the CATEGORY beside it — the exact pair `#saving_toward_a_target?` mistook for a fund — and that
    # column is dropped, so the shape is the only classifier left.
    it "leaves out a category whose rule resets" do
      envelope = create(:category, :expense, :funded, user: user, name: "Groceries")
      create(:budget, :per_period_rate, category: envelope, amount: 400)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end

    # A GOAL ON A CATEGORY THAT HAS NOT STARTED COUNTING is not money being saved yet:
    # `funded_since` is where `ClaimCalculator`'s walk opens, and the Budget page's "not filling"
    # band is where that state is named. A strip about savings is not where a user should first
    # learn it.
    it "leaves out a goal on a category with no holding date" do
      one_day = create(:category, :expense, user: user, name: "One Day", funded_since: nil)
      create(:budget, :by_date, category: one_day, amount: 5_000)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end
  end

  describe "a fund's card", :aggregate_failures do
    # $1,000 of a $5,000 target: one walked period of a $1,000-a-period rule, nothing spent.
    let!(:vacation) { goal("Vacation Fund", 5_000, accrues: 1_000) }

    it "shows the claim against the target, and no per-period flow" do
      visit reports_path

      within(card(vacation)) do
        expect(page).to have_content("$1,000.00")
        expect(page).to have_content("of $5,000.00")
        expect(page).to have_no_content("In")
        expect(page).to have_no_content("Out")
      end
    end

    # ** THE HEADING SAYS `Claimed`, NOT `Total`. ** "Total" read as "total saved" over a figure that
    # is now a sum of CLAIMS — money rules speak for where it sits, rather than money moved into
    # goals — and Home's own word for that is claimed.
    it "heads the strip with what the funds claim between them" do
      goal("Car Fund", 4_000, accrues: 500)

      visit reports_path

      expect(page).to have_content("Claimed:")
      expect(page).to have_content("$1,500.00")
    end

    # BOTH DIRECTIONS ON THE TAB THAT IS GONE. `?tab=savings` is a stale bookmark now, and
    # DashboardController checks the parameter against its own list rather than trusting it — so it
    # lands on All, which still renders this strip, instead of on an empty panel under a tab strip.
    it "is still reached by a stale ?tab=savings bookmark, which lands on All" do
      visit reports_path(tab: "savings")

      expect(page).to have_no_link("Savings")
      expect(find("nav[aria-label='Tabs'] a", text: "All")[:class]).to include("border-brand")
      expect(page).to have_css("[data-savings-strip]")
    end

    # ** SPENDING FROM A GOAL DROPS ITS CLAIM BY WHAT WAS SPENT (§3.2's fulfilment), AND THE CLAMP IS
    # WHAT KEEPS IT OFF THE FLOOR. ** The walk is
    # `clamp(min(0 + 1,000, 5,000) − 400, 0, 5,000)` = $600, and this is the surviving half of the
    # deleted "negative badge" example: a claim cannot go below zero, so the card never draws one.
    it "drops by what was spent, and stops at nothing rather than going below it" do
      spend(vacation, 400)

      visit reports_path

      within(card(vacation)) { expect(page).to have_content("$600.00") }
      expect(page).to have_no_content("negative")
    end

    it "reads nothing rather than a negative when the spending outruns the claim" do
      spend(vacation, 1_400)

      visit reports_path

      within(card(vacation)) { expect(page).to have_content("$0.00") }
      expect(page).to have_no_content("negative")
    end

    # ** A FUND WITH A SIBLING RULE SHOWS ITS OWN BUILT-UP AND NO CEILING (spec §10.5; fix wave —
    # MED-1). ** The row was `ClaimLedger#claim_of_category` — Σ EVERY rule on the category — printed
    # against ONE rule's `target_amount`, and the heading over the strip sums those rows under the
    # word "Claimed". A car insurance bill accruing beside a car fund was counted as savings and
    # measured against the fund's ceiling.
    #
    # PLANTED, RE-DERIVED. The period is biweekly anchored today and both rules are written now, so
    # each walks exactly ONE period:
    #
    #   the FUND  item-less, $2,400 four fortnights out → planned `2,400 ÷ 4` = 600 → built up
    #             **$600.00**
    #   the BILL  on the item "Insurance", $600 due three days out — inside this period, so
    #             `periods_left` is 1 and the catch-up asks the whole $600 → built up **$600.00**
    #
    # The card read `$1,200.00 of $2,400.00` — half full over a fund a QUARTER full — and the strip's
    # heading read $2,200.00 against the $1,000 Vacation Fund beside it. It says **$600.00 built up**
    # now, with `$1,600.00` over the strip. The "of $2,400.00" absence is asserted on the CARD rather
    # than the page, because the Vacation Fund's own `of $5,000.00` is a legitimate neighbour.
    # THE BILL IS ITEM-BACKED BECAUSE IT HAS TO BE: `Budget#category_may_hold_one_item_less_rule`
    # allows exactly one rule whose lane is the whole category, and the fund is it.
    def car_fund_beside_its_insurance_bill
      car = goal("Car Fund", 2_400, accrues: 600)
      create(
        :budget,
        category: car,
        item: create(:item, category: car, name: "Insurance"),
        amount: 600,
        interval_months: nil,
        anchor_date: Date.current + 3.days
      )
      car
    end

    it "shows a fund's own built-up and no ceiling where it is not the whole category" do
      car = car_fund_beside_its_insurance_bill

      visit reports_path

      # THE BADGE IS "on the way" AND NOT "saving" (fix wave — LOW-5): the card says what the fund is
      # doing because it has no ceiling to be a fraction of, in the app's own words rather than the
      # strip's private ones.
      within(card(car)) do
        expect(page).to have_content("$600.00")
        expect(page).to have_content("built up")
        expect(page).to have_content("on the way")
        expect(page).to have_no_content("of $2,400.00")
      end
      expect(page).to have_content("$1,600.00")
    end
  end

  # `progress_percentage` is `(claim ÷ target × 100).round.clamp(0, 100)` —
  # `HoldingCalculator#progress_percentage`'s arithmetic, kept to the character so no figure moved in
  # the conversion. All four badge arms are reachable now that the strip holds rule-fed goals, and
  # each is planted at the figure that reaches it rather than described.
  describe "the badges", :aggregate_failures do
    it "shows 'low' under a tenth of the way there" do
      big = goal("Big Goal", 20_000, accrues: 1_000) # 1,000 / 20,000 = 5%

      visit reports_path

      within(card(big)) { expect(page).to have_content("low") }
    end

    it "shows the percentage between a tenth and a half" do
      trip = goal("Trip", 5_000, accrues: 1_000) # 20%

      visit reports_path

      within(card(trip)) { expect(page).to have_content("20%") }
    end

    it "shows the percentage from a half up" do
      roof = goal("Roof", 2_000, accrues: 1_000) # 50%

      visit reports_path

      within(card(roof)) { expect(page).to have_content("50%") }
    end

    # `planned_for` CAPS THE PERIOD'S ACCRUAL AT WHAT IS STILL MISSING (§3.2), so a $1,000 rule on a
    # $1,000 target lands exactly on it in one period rather than overshooting.
    #
    # ** THE WORD IS "ready", NOT "funded" (fix wave — LOW-5). ** `ready` is what Home's own rows say
    # of a fund that has reached its figure (`HomeHelper#when_words`), and a strip using a private
    # vocabulary for the state the row beside it already names is two words for one fact.
    it "says 'ready' once the claim reaches the target" do
      small = goal("Small Goal", 1_000, accrues: 1_000) # 100%

      visit reports_path

      within(card(small)) do
        expect(page).to have_content("ready")
        expect(page).to have_no_content("low")
      end
    end

    # ** A SPENT GOAL IS "achieved", AND IT WAS THE STRIP'S WORST SENTENCE (fix wave — MED-3). **
    # Paying for the holiday empties the fund, so `#built_up` is $0.00 and every figure-reading arm
    # here called it `low` — a warning at the user who has just done the thing. `ClaimLine#paid?`
    # (`ClaimCalculator#settled?`) is the reader, and the card says what the goal WAS and when it
    # was met rather than what is left of it.
    #
    # RE-DERIVED: a $5,000 goal accruing $1,000 a period, with $5,000 spent on its lane today —
    # `walk.paid` reaches the target, so the rule is settled today. `#built_up` clamps to $0.00.
    it "says 'achieved' on a goal that has been spent, with no bar", :aggregate_failures do
      vacation = goal("Vacation", 5_000, accrues: 1_000)
      spend(vacation, 5_000)

      visit reports_path

      within(card(vacation)) do
        expect(page).to have_content("achieved")
        expect(page).to have_content("$5,000.00")
        expect(page).to have_no_content("low")
        expect(page).to have_no_content("of $5,000.00")
      end
    end

    # THE OTHER DIRECTION: one dollar short of the target is not paid, and the card goes back to
    # saying how far along it is — over the SAME $0.00 built-up, which is what makes `#paid?` a
    # reader the strip cannot do without.
    it "keeps calling a goal one dollar short low", :aggregate_failures do
      vacation = goal("Vacation", 5_000, accrues: 1_000)
      spend(vacation, 4_999)

      visit reports_path

      within(card(vacation)) do
        expect(page).to have_content("low")
        expect(page).to have_content("of $5,000.00")
        expect(page).to have_no_content("achieved")
      end
    end
  end
end
