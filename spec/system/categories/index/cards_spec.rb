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

  before { sign_in user, scope: :user }

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

      # The card is an `<a>`, so the spec asks for a LINK — a claim about the affordance rather
      # than about the class attribute it happens to carry.
      click_link expense_category.name
      expect(page).to have_current_path(category_path(expense_category))
    end

    # `first`: the sidebar renders the date selector twice — mobile and desktop — and both submit
    # the same GET, so under Rack::Test either control is the control.
    it "updates the spending when navigating to next month via navbar and keeps type" do
      first("button[title='Next month']").click

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content(currency(300))
      expect(page).to have_content("-#{currency(200)}")
      expect(page).to have_content("-#{currency(100)}")
    end

    it "updates the spending when navigating to previous month via navbar" do
      first("button[title='Previous month']").click

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
      first("button[title='Next month']").click

      expect(page).to have_content(currency(1000))
      expect(page).to have_content("+#{currency(700)}")
      expect(page).to have_content("+#{currency(300)}")
    end
  end

  describe "what a card says about the money the category claims", :aggregate_failures do
    # A monthly grid anchored the 1st, so every rule below opens its accrual walk in the current
    # period and visits exactly one — the figures are arithmetic rather than calendar luck.
    before { user.update!(period_cadence: :monthly, period_anchor_date: base_date) }

    let(:due_on) { (base_date + 4.months) - 1.day }

    # PLANTED: a $2,000 goal due at the close of the fourth month from this one, its walk opening
    # in this period. Four boundaries remain, so `planned = 2,000 ÷ 4` = $500.00, nothing is spent,
    # the claim is $500.00 and the bar is `(500 ÷ 2,000 × 100).round` = 25.
    def goal_on(category)
      create(
        :rule,
        :choice,
        category: category,
        amount: 2_000,
        interval_months: nil,
        anchor_date: due_on,
        starts_on: base_date
      )
    end

    it "shows a goal's claim and its progress toward the rule's target" do
      goal_on(create(:category, :expense, user: user, name: "Vacation"))

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(500))
      expect(page).to have_css("[data-holdings-progress]")
      expect(page).to have_content("25% of #{currency(2_000)}")
    end

    # `Claimed` is Σ EVERY rule's claim and the target is a ceiling on the GOAL's built-up alone,
    # so beside a sibling rule the two are different money and no ceiling can be printed.
    #
    # PLANTED: the goal above ($500.00 built up) beside an item-backed $100.00-a-period rate rule
    # with nothing spent against it — `max(0, 100 + 0 − 0)`. Their sum is $600.00.
    def goal_beside_a_rate_rule
      vacation = create(:category, :expense, user: user, name: "Vacation")
      goal_on(vacation)
      create(
        :rule,
        :rate,
        category: vacation,
        amount: 100,
        starts_on: base_date,
        item: create(:item, category: vacation, name: "Flights")
      )
    end

    it "draws no bar for a goal that is not the whole category" do
      goal_beside_a_rate_rule

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(600))
      expect(page).to have_no_css("[data-holdings-progress]")
      expect(page).to have_no_content("of #{currency(2_000)}")
    end

    # A bill is a thing that must be PAID rather than a thing being saved for, so it draws no
    # track however it accrues.
    #
    # PLANTED: $2,400 every six months, first due at the close of the fourth month from this one,
    # so four boundaries remain and `planned = 2,400 ÷ 4` = $600.00 in the one period walked.
    def repeating_bill_on(category)
      create(
        :rule,
        :bill,
        category: category,
        amount: 2_400,
        interval_months: 6,
        anchor_date: due_on,
        starts_on: base_date
      )
    end

    it "shows a repeating bill's claim and no bar" do
      repeating_bill_on(create(:category, :expense, user: user, name: "Emergency"))

      visit categories_path(type: "expense")

      expect(page).to have_content(currency(600))
      expect(page).to have_no_css("[data-holdings-progress]")
    end

    # A rate rule claims money too — it just has no target for a bar to be a fraction of.
    #
    # PLANTED: `max(0, rate + Σ adjustments − spent)` = `max(0, 400 + 0 − 0)` = $400.00.
    it "shows a rate rule's claim and no bar" do
      create(:rule, :rate, category: create(:category, :expense, user: user, name: "Groceries"), amount: 400)

      visit categories_path(type: "expense")

      expect(page).to have_content("Claimed")
      expect(page).to have_content(currency(400))
      expect(page).to have_no_css("[data-holdings-progress]")
    end

    # The fragment cache this card used to sit in keyed on the category row, which a change to the
    # PERIOD GRID does not touch — so the card went on printing the old figure. The store is turned
    # on for real here, or the removal proves nothing: with a null store every arrangement passes.
    describe "the claim is never served stale" do
      around do |example|
        cache = Rails.cache
        controller_cache = ActionController::Base.cache_store
        caching = ActionController::Base.perform_caching

        Rails.cache = ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
        ActionController::Base.perform_caching = true
        example.run
      ensure
        Rails.cache = cache
        ActionController::Base.cache_store = controller_cache
        ActionController::Base.perform_caching = caching
      end

      it "re-reads the claim when the period grid moves under it" do
        goal_on(create(:category, :expense, user: user, name: "Vacation"))

        visit categories_path(type: "expense")
        expect(page).to have_content("25% of #{currency(2_000)}")

        user.update!(period_cadence: :weekly)
        visit categories_path(type: "expense")

        expect(page).to have_content("Claimed")
        expect(page).to have_no_content("25% of #{currency(2_000)}")
      end
    end
  end
end
