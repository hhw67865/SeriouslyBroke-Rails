# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Cards", type: :system do
  def currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  let!(:user) { create(:user) }

  # Shared dates based on current month
  let(:base_date) { Date.current.beginning_of_month }
  let(:next_date) { base_date.next_month }
  let(:prev_date) { base_date.prev_month }

  before do
    sign_in user, scope: :user
  end

  # THE CARD'S CAP ARM IS DELETED (plan 3, task 3), its POOL LINE with it (Task 7), and its HOLDING
  # line with the moved money (computed-claims spec §5, Task 4). The card printed "Pool: Checking",
  # then a `HoldingCalculator#balance`; it prints what the category's rules CLAIM now, or — where no
  # rule claims it — that its spending comes straight out of what's free to spend. There is no
  # `available` to come out of: `free` is a DEFINITION (`min(pot, total − Σ claims)`, §2) rather than
  # a pot. The spending figures and the month navigation are unchanged.
  describe "expense card shows the period's spending and links to show", :aggregate_failures do
    let!(:expense_category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
    let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }

    before do
      # Month A entries (total 150)
      create(:entry, item: groceries_item, amount: 100, date: base_date + 2.days)
      create(:entry, item: dining_item, amount: 50, date: base_date + 10.days)
      # Previous month entries (total 120)
      create(:entry, item: groceries_item, amount: 70, date: prev_date + 3.days)
      create(:entry, item: dining_item, amount: 50, date: prev_date + 9.days)
      # Month B entries (total 300)
      create(:entry, item: groceries_item, amount: 200, date: next_date + 5.days)
      create(:entry, item: dining_item, amount: 100, date: next_date + 12.days)

      visit categories_path(type: "expense", month: base_date.month, year: base_date.year)
    end

    it "displays the period's spending, its lane and the top items for selected month" do
      expect(page).to have_content(currency(150))
      expect(page).to have_content("Nothing claims this — comes out of what's free to spend")
      expect(page).to have_no_content("% used")

      # Top items with amounts (expense shows negative sign)
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")
      expect(page).to have_content("-#{currency(100)}")
      expect(page).to have_content("-#{currency(50)}")

      # `click_link`, WHERE THIS USED TO BE `find("div.group.cursor-pointer").click` (design review
      # B1). The card was a `<div onclick="window.location=…">` — no href, no tab stop, no focus
      # ring, nothing for a screen reader — and the selector was the assertion agreeing with it: it
      # could only pass against markup a keyboard user cannot reach. The card is an `<a>` now, so
      # the spec asks Capybara for a LINK, which is a claim about the affordance and not about the
      # class attribute it happens to carry.
      click_link expense_category.name
      expect(page).to have_current_path(category_path(expense_category))
    end

    it "updates the spending when navigating to next month via navbar and keeps type" do
      find("button[title='Next month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(300))
      expect(page).to have_content("-#{currency(200)}")
      expect(page).to have_content("-#{currency(100)}")
    end

    it "updates the spending when navigating to previous month via navbar" do
      find("button[title='Previous month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(120))
    end
  end

  describe "income card shows correct monthly income and links to show", :aggregate_failures do
    let!(:income_category) { create(:category, category_type: "income", user: user, name: "Salary") }
    let!(:paycheck_item) { create(:item, category: income_category, name: "Paycheck") }
    let!(:bonus_item) { create(:item, category: income_category, name: "Bonus") }

    before do
      # Previous month baseline for % change (500)
      create(:entry, item: paycheck_item, amount: 500, date: base_date.prev_month + 5.days)
      # Current month (750)
      create(:entry, item: paycheck_item, amount: 500, date: base_date + 1.day)
      create(:entry, item: bonus_item, amount: 250, date: base_date + 15.days)
      # Next month (1000)
      create(:entry, item: paycheck_item, amount: 700, date: next_date + 3.days)
      create(:entry, item: bonus_item, amount: 300, date: next_date + 10.days)

      visit categories_path(type: "income", month: base_date.month, year: base_date.year)
    end

    it "displays correct monthly income, percentage change, and top items for selected month" do
      expect(page).to have_content(currency(750))
      # 50% up vs last month (750 vs 500)
      expect(page).to have_content("50%")

      # Top items with positive amounts
      expect(page).to have_content("Paycheck")
      expect(page).to have_content("Bonus")
      expect(page).to have_content("+#{currency(500)}")
      expect(page).to have_content("+#{currency(250)}")

      click_link income_category.name
      expect(page).to have_current_path(category_path(income_category))
    end

    it "updates income info when navigating to next month via navbar" do
      find("button[title='Next month']").click

      expect(page).to have_content(currency(1000))
      expect(page).to have_content("+#{currency(700)}")
      expect(page).to have_content("+#{currency(300)}")
    end
  end

  # THE SAVINGS CARD IS BACK, AS A CATEGORY (two-ledger spec §3, Task 7), AND ITS FIGURE IS A CLAIM
  # (computed-claims spec §2, Task 4). It was deleted with the savings TYPE in plan 3 task 5 — its
  # two examples read a "Monthly Contribution" figure and a "Savings Pool: Main Pool" line off a card
  # arm that no longer existed — and savings now live here, on the screen that replaced the Pools
  # index. The classifier is `Category#building_rule` (rules-own-the-budget spec §5) — the item-less
  # rule whose unspent money carries — the same reader the show page's holdings card and the entry
  # form's impact card ask. It replaced `Category#saving_toward_a_target?`, a question about a figure
  # on the CATEGORY that no claim formula has read since the shapes moved onto the rule.
  #
  # ** BOTH FIXTURES USED TO BE ALLOCATIONS AND ARE NOW RULES. ** Nothing moves on the purpose side
  # (§5), so the $500 that was moved into Vacation and the $400 moved into Groceries are written the
  # way the model actually puts money there — a rule that accrues, and a rate rule — and both figures
  # are re-derived below. The 25% is deliberately the SAME 25% the allocation version asserted: the
  # reading of a goal against its target did not change, only what the numerator is made of.
  describe "what a card says about the money the category claims", :aggregate_failures do
    # PLANTED (§3.2's dateless branch): a $500-per-period rule on a $2,000 goal, funded a year back
    # but written today, so the accrual walk opens in the current period and visits exactly one.
    # `planned = min(rate, gap)` = `min(500, 2,000)` = **$500.00**, nothing is spent, so the claim is
    # $500.00 and the bar is `(500 ÷ 2,000 × 100).round` = **25**.
    it "shows a fund's claim and its progress toward the rule's target" do
      vacation = create(:category, :expense, :funded, user: user, name: "Vacation")
      create(:budget, :capped, category: vacation, amount: 500, target_amount: 2_000)

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(500))
      expect(page).to have_css("[data-building-progress]")
      expect(page).to have_content("25% of #{currency(2_000)}")
    end

    # ** A FUND WITH A SIBLING RULE PRINTS NO CEILING (spec §10.5; fix wave — MED-1). ** `Claimed` is
    # Σ EVERY rule's claim and the target is a ceiling on the FUND's built-up alone, so `25% of
    # $2,000.00` measured one against the other: the card said a $2,000 fund was a quarter of the way
    # there while counting a second rule's money into the numerator. The entry form's impact card had
    # this guard since §10.5 and this card did not.
    #
    # PLANTED: the example above's fund — $500 a period toward $2,000, one walked period, **$500.00**
    # built up — plus an item-backed **$100.00**-a-period rate rule with nothing spent against it
    # (§3.1: `max(0, 100 + 0 − 0)`). `Claimed` is their sum, **$600.00**, and the fund's own figure is
    # still $500 — which is exactly why no ceiling can be printed beside the $600.
    #
    # THE SIBLING IS A RATE RULE AND NOT THE §10.5 EXAMPLE'S DATED BILL: this file's user declares no
    # period, so the walk falls back to the calendar month and a dated rule's catch-up would depend
    # on which day of the month the suite ran (CLAUDE.md's third flake cause). What the gate reads is
    # that a SECOND rule exists, and a rate rule is the cheapest honest way to say so.
    def vacation_fund_beside_a_second_rule
      vacation = create(:category, :expense, :funded, user: user, name: "Vacation")
      create(:budget, :capped, category: vacation, amount: 500, target_amount: 2_000)
      create(
        :budget,
        :per_period_rate,
        category: vacation,
        item: create(:item, category: vacation, name: "Flights"),
        amount: 100
      )
    end

    it "draws no bar for a fund that is not the whole category", :aggregate_failures do
      vacation_fund_beside_a_second_rule

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(600))
      expect(page).to have_no_css("[data-building-progress]")
      expect(page).to have_no_content("of #{currency(2_000)}")
    end

    # ** AN UNCAPPED FUND HAS NO TRACK (rules-own-the-budget spec §2.1 row 2). ** Same shape, same
    # walk, no ceiling: `planned` is the plain rate because there is no `gap` to bound it, so the
    # claim is **$500.00** and there is nothing for a bar to be a fraction of. Both halves, so a card
    # that drew an empty or a full track against no figure would fail here.
    it "shows an uncapped fund's claim and no bar", :aggregate_failures do
      emergency = create(:category, :expense, :funded, user: user, name: "Emergency")
      create(:budget, :building, category: emergency, amount: 500)

      visit categories_path(type: "expense")

      expect(page).to have_content(currency(500))
      expect(page).to have_no_css("[data-building-progress]")
    end

    # ** THE OTHER DIRECTION, AND IT IS THE ONE THE OLD CLASSIFIER GOT WRONG. ** A figure on the
    # CATEGORY beside a rule whose money RESETS drew a bar against a number no formula reads. The
    # shape decides now, and this shape is an envelope — `categories.target_amount` is dropped
    # (§6/§7), so there is no second number for a classifier to be tempted by.
    it "draws no bar for a resetting rule", :aggregate_failures do
      groceries = create(:category, :expense, :funded, user: user, name: "Groceries")
      create(:budget, :per_period_rate, category: groceries, amount: 400)

      visit categories_path(type: "expense")

      expect(page).to have_content(currency(400))
      expect(page).to have_no_css("[data-building-progress]")
    end

    # An envelope claims money too — it just has no target for a bar to be a fraction of.
    #
    # PLANTED (§3.1): `max(0, rate + Σ adjustments − spent)` = `max(0, 400 + 0 − 0)` = **$400.00**.
    it "shows an envelope's claim and no bar" do
      groceries = create(:category, :expense, :funded, user: user, name: "Groceries")
      create(:budget, :per_period_rate, category: groceries, amount: 400)

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(400))
      expect(page).to have_no_css("[data-building-progress]")
    end

    # ** AND A HOLDER WITH NO RULE CLAIMS NOTHING (§3.3: every claim comes from a rule). ** Under the
    # moved-money model this card would have shown whatever had been allocated in; a category with a
    # funding date and no rule now has a claim of exactly zero however much has been spent on it, and
    # the card says so rather than leaving the line off.
    it "shows a claim of nothing for a holder with no rule" do
      create(:category, :expense, :funded, user: user, name: "Cushion")

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(0))
    end
  end
end
