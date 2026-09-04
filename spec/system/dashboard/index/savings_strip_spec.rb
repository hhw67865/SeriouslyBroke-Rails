# frozen_string_literal: true

require "rails_helper"

# THE GOALS STRIP ON THE ALL TAB (plan 3, task 5), ABOUT CATEGORIES (two-ledger spec §3, Task 7),
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
# migrated data.** Its classifier is `Category#saving_toward_a_target?` now — a funding start and a
# figure to reach — which is the one goal predicate left in the app, and `#savings?` is deleted with
# its last caller. The population is pinned in four directions below, because a band that silently
# stops appearing is indistinguishable from one that broke.
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
  def goal(name, target, accrues:)
    category = create(
      :category, :expense, user: user, name: name, target_amount: target, funded_since: 1.year.ago.to_date
    )
    create(:budget, :per_period_rate, category: category, amount: accrues)
    category
  end

  # A GOAL NO RULE FEEDS: the same thing without one. It is still a goal — the classifier asks about
  # the TARGET, not about the money — and under §3.3 it claims exactly nothing.
  def ruleless_goal(name, target)
    create(
      :category, :expense, user: user, name: name, target_amount: target, funded_since: 1.year.ago.to_date
    )
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

    # AND IT STILL HOLDS THE OTHER SHAPE, claiming a truthful nothing: the classifier is about the
    # target, so a goal nobody has fed is a goal with an empty bar rather than an absent row.
    it "holds a goal no rule feeds, at nothing" do
      someday = ruleless_goal("Someday", 5_000)

      visit reports_path

      expect(someday.claim).to eq(0)
      within(card(someday)) do
        expect(page).to have_content("$0.00")
        expect(page).to have_content("of $5,000.00")
      end
    end

    it "leaves out a category with no figure to reach" do
      envelope = create(:category, :expense, :funded, user: user, name: "Groceries")
      create(:budget, :per_period_rate, category: envelope, amount: 400)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end

    # A TARGET ON A CATEGORY THAT HAS NOT STARTED COUNTING is not a goal anything is being saved
    # into: `funded_since` is where `ClaimCalculator`'s walk opens, so there is no span for a claim
    # to accrue over.
    it "leaves out a target on a category with no holding date" do
      create(:category, :expense, user: user, name: "One Day", target_amount: 5_000, funded_since: nil)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end
  end

  describe "a goal's card", :aggregate_failures do
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
    it "heads the strip with what the goals claim between them" do
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
    it "says 'funded' once the claim reaches the target" do
      small = goal("Small Goal", 1_000, accrues: 1_000) # 100%

      visit reports_path

      within(card(small)) do
        expect(page).to have_content("funded")
        expect(page).to have_no_content("low")
      end
    end
  end
end
