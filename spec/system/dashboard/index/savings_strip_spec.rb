# frozen_string_literal: true

require "rails_helper"

# The savings strip on the All tab. A goal is a one-off dated rule whose amount is its target, and
# its figure is a claim: `Σ` of what the rule's walk has built up, not a balance anything moved.
# The population is pinned in four directions, because a band that silently stops appearing is
# indistinguishable from one that broke.
RSpec.describe "Dashboard Index - Savings strip", type: :system do
  # A declared biweekly period anchored today, and it is not decoration: a claim is a walk over
  # periods, so a user with no cadence falls back to the calendar month and the arithmetic moves
  # with the day the suite runs on. Anchored today, every rule below walks exactly one period.
  let!(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }

  before { sign_in user, scope: :user }

  # A goal accruing `accrues` a period: the horizon is derived from the pair, so `target / accrues`
  # fortnights out leaves exactly that many boundaries and the first period asks `accrues`.
  def goal(name, target, accrues:)
    category = create(:category, :expense, user: user, name: name)
    create(
      :rule,
      category: category,
      item: nil,
      amount: target,
      starts_on: Date.current,
      anchor_date: Date.current + ((14 * (target / accrues)) - 1).days,
      interval_months: nil
    )
    category
  end

  def spend(category, amount, on: Date.current)
    item = category.items.find_by(name: "Spending") || create(:item, category: category, name: "Spending")
    create(:entry, item: item, amount: amount, date: on)
  end

  def card(category) = find("[data-savings-strip] a[href='#{category_path(category)}']")

  describe "which categories the strip holds", :aggregate_failures do
    it "holds a goal a rule feeds, which is every goal with money in it" do
      vacation = goal("Vacation Fund", 5_000, accrues: 1_000)

      visit reports_path

      within(card(vacation)) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00")
        expect(page).to have_content("of $5,000.00")
      end
    end

    it "holds a goal whose date is far enough out that it has barely started", :aggregate_failures do
      someday = goal("Someday", 5_000, accrues: 5)

      visit reports_path

      within(card(someday)) do
        expect(page).to have_content("$5.00")
        expect(page).to have_content("of $5,000.00")
      end
    end

    # Four fortnights out, the same horizon `#goal` derives, so the only difference between these
    # two rules and a goal is the clause under test.
    def dated_rule(name, amount, type: :usage, interval_months: nil)
      category = create(:category, :expense, user: user, name: name)
      create(
        :rule,
        type,
        category: category,
        item: nil,
        amount: amount,
        starts_on: Date.current,
        anchor_date: Date.current + 55.days,
        interval_months: interval_months
      )
    end

    # A rule that repeats is a recurring bill and has no card: it accrues by exactly the same walk
    # as a goal, and the water rates every six months are not something being saved toward.
    it "leaves out a category whose only dated rule repeats" do
      dated_rule("Water", 1_000, interval_months: 6)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end

    # A rule that resets every period claims its money again, whatever else is true of its category.
    it "leaves out a category whose rule resets" do
      groceries = create(:category, :expense, user: user, name: "Groceries")
      create(:rule, :rate, category: groceries, amount: 400)

      visit reports_path

      expect(page).to have_no_css("[data-savings-strip]")
    end

    # A one-off the user typed `bill` has the same four columns as a goal and accrues by the same
    # walk, so nothing in the shape can tell them apart. The word the user chose can, and a band
    # headed "Savings" listing the household's tax estimate would name money as saved that has to
    # be handed over. The goal beside it renders, from the same shape, on the same screen.
    it "leaves out a one-off bill while listing the goal beside it", :aggregate_failures do
      dated_rule("Tax Estimate", 3_000, type: :bill)
      vacation = goal("Vacation Fund", 5_000, accrues: 1_000)

      visit reports_path

      within("[data-savings-strip]") { expect(page).to have_no_content("Tax Estimate") }
      within(card(vacation)) { expect(page).to have_content("$1,000.00") }
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

    # The heading says "Claimed", not "Total": the figure is a sum of claims, which is Home's own
    # word for money rules speak for.
    it "heads the strip with what the funds claim between them" do
      goal("Car Fund", 4_000, accrues: 500)

      visit reports_path

      expect(page).to have_content("Claimed:")
      expect(page).to have_content("$1,500.00")
    end

    # Both directions on the tab that is gone: `?tab=savings` lands on All, which still renders
    # this strip, rather than on an empty panel under a tab strip.
    it "is still reached by a stale ?tab=savings bookmark, which lands on All" do
      visit reports_path(tab: "savings")

      within("nav[aria-label='Tabs']") { expect(page).to have_no_link("Savings") }
      expect(find("nav[aria-label='Tabs'] a", text: "All")[:class]).to include("border-brand")
      expect(page).to have_css("[data-savings-strip]")
    end

    # The walk is `clamp(min(0 + 1,000, 5,000) − 400, 0, 5,000)` = $600.
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

    # A fund sharing its category with another rule shows its own built-up and no ceiling: the
    # target is a ceiling on the fund's money, and the figure beside it would be the category's.
    #
    # The fund is item-less, $2,400 four fortnights out, so it asks `2,400 ÷ 4` = $600. The bill is
    # on an item, $600 due three days out — inside this period, so the catch-up asks the whole
    # $600. The card says $600.00 built up, with $1,600.00 over the strip beside the Vacation Fund.
    def car_fund_beside_its_insurance_bill
      car = goal("Car Fund", 2_400, accrues: 600)
      create(
        :rule,
        category: car,
        item: create(:item, category: car, name: "Insurance"),
        amount: 600,
        starts_on: Date.current,
        anchor_date: Date.current + 3.days,
        interval_months: nil
      )
      car
    end

    it "shows a fund's own built-up and no ceiling where it is not the whole category" do
      car = car_fund_beside_its_insurance_bill

      visit reports_path

      within(card(car)) do
        expect(page).to have_content("$600.00")
        expect(page).to have_content("built up")
        expect(page).to have_content("on the way")
        expect(page).to have_no_content("of $2,400.00")
      end
      expect(page).to have_content("$1,600.00")
    end
  end

  # `progress_percentage` is `(claim ÷ target × 100).round.clamp(0, 100)`. Each badge arm is
  # planted at the figure that reaches it rather than described.
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

    # The period's accrual is capped at what is still missing, so a $1,000 rule on a $1,000 target
    # lands exactly on it in one period. The word is "ready", which is what Home's own rows say of
    # a fund that has reached its figure.
    it "says 'ready' once the claim reaches the target" do
      small = goal("Small Goal", 1_000, accrues: 1_000) # 100%

      visit reports_path

      within(card(small)) do
        expect(page).to have_content("ready")
        expect(page).to have_no_content("low")
      end
    end

    # Paying for the holiday empties the fund, so its built-up is $0.00 and every figure-reading
    # arm would call it "low" — a warning at the user who has just done the thing they saved for.
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

    # The other direction: one dollar short is not paid, over the same $0.00 built-up — which is
    # what makes `#paid?` a reader the strip cannot do without.
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
