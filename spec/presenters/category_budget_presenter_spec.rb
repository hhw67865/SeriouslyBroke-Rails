# frozen_string_literal: true

require "rails_helper"

# ** THE FUND FIGURE ON THE CATEGORY CARDS (rules-own-the-budget spec §5, §10.5). **
#
# This class draws the SAME bar on two screens — the categories index card and the categories show
# page's holdings card — and until the fix wave it summed EVERY rule's claim and divided by ONE
# rule's target. `EntryImpactPresenter` had already been given §10.5's guard; these two had not, so a
# "Car" category carrying a fund beside an insurance bill read half full on three screens while its
# fund was a quarter full.
#
# ** WHAT IS HERE AND WHY IT IS NOT IN THE SYSTEM SPECS. ** The two screens pin the RENDERED
# sentence (`cards_spec`, `holdings_spec`); what a browser cannot say cheaply is that the four
# readers agree — `#claim`, `#fund_figure`, `#target` and `#progress_percentage` — on one fixture,
# in both directions, with the arithmetic re-derived rather than described.
#
# `today:` IS PASSED EXPLICITLY rather than travelled to, so no example reads `Date.current` inside a
# frozen clock (CLAUDE.md's third flake cause).
RSpec.describe CategoryBudgetPresenter do
  # Feb 6 is the anchor AND the day, so the current period runs Feb 6–19 — `entry_impact_presenter
  # _spec`'s own clock, because the mixed fixture below is that file's fixture and the two must be
  # readable against each other.
  let(:today) { Date.new(2026, 2, 6) }
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end

  # A LITERAL rather than `1.year.ago`: this file's clock is fixed at Feb 2026 and a wall-clock
  # funding date would slide past it in a real year.
  let(:funded_since) { Date.new(2025, 1, 1) }

  # THE DAY AN ACCRUING RULE WAS BORN (§3.2). A rule accrues from the LATER of its category's funding
  # date and its own creation, so a rule the factory writes at the real wall clock — months after
  # this file's `today` — walks NO periods and holds nothing. Born as the current period opens, every
  # rule below walks exactly ONE period, which is what makes the literals readable.
  def born = Time.utc(2026, 2, 6, 9, 0)

  def present(category) = described_class.new(category: category.reload, today: today)

  # ** THE MIXED FIXTURE, RE-DERIVED BY HAND (§10.5's own example). ** "Car", funded Jan 1 2025, both
  # rules born as the current period opens, so each walks exactly ONE period:
  #
  #   the FUND  item-less, $2,400 by Apr 2 — FOUR biweekly boundaries from Feb 6 (Feb 6, Feb 20,
  #             Mar 6, Mar 20), so the catch-up share is `2,400 ÷ 4` = $600 and nothing is spent →
  #             built up **$600.00**
  #   the BILL  on the item "Insurance", $600 due Feb 9 — inside the Feb 6–19 period, so
  #             `periods_left` is 1 and the catch-up asks the whole $600 → built up **$600.00**
  #
  # Σ claims **$1,200.00**, which against the fund's $2,400 reads `50% of $2,400.00` — half full over
  # a fund that is a QUARTER full.
  #
  # ** THE FUND WAS A $600-A-PERIOD RULE CAPPED AT $2,400 (two-shapes §2). ** The horizon replaces the
  # rate and every figure here is unchanged, which is what let the shape be retired rather than
  # replaced.
  def car_fund
    car = create(:category, :expense, user: user, name: "Car", funded_since: funded_since)
    create(
      :budget,
      category: car,
      amount: 2_400,
      basis: :monthly,
      interval_months: nil,
      anchor_date: Date.new(2026, 4, 2),
      created_at: born
    )
    car
  end

  # THE SIBLING IS ITEM-BACKED BECAUSE IT HAS TO BE: `Budget#category_may_hold_one_item_less_rule`
  # allows exactly one rule whose lane is the whole category, and the fund is it.
  def insurance_bill_on(car)
    create(
      :budget,
      category: car,
      item: create(:item, category: car, name: "Insurance"),
      amount: 600,
      interval_months: nil,
      anchor_date: today + 3.days,
      created_at: born
    )
  end

  describe "the fund's figure and its ceiling", :aggregate_failures do
    # ** THE DEFECT, AS FIGURES (fix wave — MED-1). ** `#claim` is honest and stays — it is the
    # CATEGORY's money and the card labels it `Claimed` — but the target is a ceiling on the FUND's
    # built-up, so with a sibling rule present there is no ceiling to print and no bar to draw.
    # `#fund_figure` is the fund's own $600.00, which is the figure the impact card falls back to.
    it "prints no ceiling where the fund is not the whole category" do
      car = car_fund
      insurance_bill_on(car)

      money = present(car)

      expect(money.fund?).to be(true)
      expect(money.claim).to eq(BigDecimal("1200"))
      expect(money.fund_is_the_only_rule?).to be(false)
      expect(money.target).to be_nil
      expect(money.bar?).to be(false)
      expect(money.progress_percentage).to eq(0)
    end

    # THE OTHER DIRECTION, ON THE SAME FIXTURE MINUS THE SIBLING: the ceiling comes back the moment
    # the fund IS the whole category, which is exactly when Σ claims and the fund's built-up are one
    # figure. `(600 ÷ 2,400 × 100).round` = **25**.
    it "prints the ceiling once the fund is the whole category" do
      money = present(car_fund)

      expect(money.claim).to eq(BigDecimal("600"))
      expect(money.fund_is_the_only_rule?).to be(true)
      expect(money.fund_figure).to eq(money.claim)
      expect(money.target).to eq(BigDecimal("2400"))
      expect(money.bar?).to be(true)
      expect(money.progress_percentage).to eq(25)
    end

    # ** THE UNCAPPED-FUND EXAMPLE IS DELETED WITH THE SHAPE (two-shapes §7). ** It planted a fund
    # that named no ceiling — the whole category, `#target` nil, and NO bar — because the two nils
    # `#target` could answer were different nils and this is what kept them apart. There is one nil
    # left, the one the example above pins: a fund with a sibling rule, whose ceiling is real and
    # whose neighbour makes it the wrong denominator.

    # ** A REPEATING BILL IS NOT A FUND, which is the one clause `Budget.saving_toward_a_date` has
    # that its predecessor could not draw. ** The water rates every two months are not something
    # being saved toward, so the card is an ENVELOPE and there is no ceiling to print — even though
    # the rule accrues exactly as a goal does.
    it "is an envelope for a rule that repeats", :aggregate_failures do
      water = create(:category, :expense, user: user, name: "Water", funded_since: funded_since)
      create(:budget, :recurring, category: water, amount: 600, anchor_date: Date.new(2026, 4, 2), created_at: born)

      money = present(water)

      expect(money.fund?).to be(false)
      expect(money.fund_is_the_only_rule?).to be(false)
      expect(money.target).to be_nil
      expect(money.bar?).to be(false)
    end

    # AN ENVELOPE HAS NO FUND AT ALL, so `#fund_figure` is nil rather than zero — the same distinction
    # `ClaimCalculator#built_up` draws between "a fund holding nothing" and "no fund".
    it "has no fund figure where nothing builds up" do
      groceries = create(:category, :expense, user: user, name: "Groceries", funded_since: funded_since)
      create(:budget, :per_period_rate, category: groceries, amount: 400, created_at: born)

      money = present(groceries)

      expect(money.fund?).to be(false)
      expect(money.fund_is_the_only_rule?).to be(false)
      expect(money.fund_figure).to be_nil
      expect(money.target).to be_nil
    end
  end
end
