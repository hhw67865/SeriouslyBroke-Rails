# frozen_string_literal: true

require "rails_helper"

# THE CATEGORIES PAGE'S HOLDINGS CARD — two states, each asserted in both directions.
#
# ONE CARD WHERE THERE WERE TWO, AND ONE FILE WHERE THERE WERE THREE (two-ledger spec §3, §5,
# Task 7). `budget_spec.rb` drove `_budget_card`, `pool_card_spec.rb` drove `_pool_card` four
# inches below it, and `savings_pool_spec.rb` pinned the noun the two of them kept disagreeing
# about. Both partials are replaced by `_holdings_card` and all three files by this one, because
# there is now one thing to describe: a category holds its own money.
#
# THE ARMS ARE `Category#holder?`'s, where they used to be the pool's TYPE. `pool_covered` and
# `account_pointed` are gone; `holding` and `unfunded` are the two states an expense category can
# be in, and the second is the whole of what "no pool" used to mean.
#
# `Capybara.exact` is unset in this suite and this page is full of chrome that matches substrings
# (the sidebar's "Budget" link, the summary card's own sentence about where spending comes from,
# the category's own name in three places), so every assertion is scoped to `[data-holdings-card]`
# and every positive is paired with a negative.
RSpec.describe "Categories Show - Holdings card", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST for income to land in
  # (`Category#income_must_land_in_an_account`), and for the category factory's own `pool` default,
  # which still names a pool for the length of this branch. Nothing on this card reads it.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  before { sign_in user, scope: :user }

  def card = find("[data-holdings-card]")

  # A category that holds its own money, funded a year back so nothing in a fixture has to say a
  # date twice.
  def holder(name, **attributes)
    create(:category, :expense, :funded, user: user, name: name, **attributes)
  end

  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount)
  end

  def allocate(category, amount, on: Date.current)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  # ------------------------------------------------------------------------------------------
  # State 1 — the category holds money
  # ------------------------------------------------------------------------------------------

  describe "a category holding its own money", :aggregate_failures do
    let!(:groceries) { holder("Groceries") }

    before do
      rate(groceries, 400)
      allocate(groceries, 400)
      visit category_path(groceries)
    end

    it "names what it is, prints the balance and links to the Budget page" do
      expect(card["data-holdings-state"]).to eq("holding")
      within(card) do
        expect(page).to have_content("Envelope")
        expect(page).to have_no_content("Goal")
        expect(page).to have_content("$400.00 left")
        expect(page).to have_link("Rules on the Budget page", href: budget_page_path)
      end
      expect(find("[data-figure='balance']").text).to eq("$400.00")
    end

    # NO EDITOR, and the negative is the point: the money a category has to spend is decided by
    # its rules and its allocations, and neither is edited here.
    it "offers no editor of its own" do
      within(card) do
        expect(page).to have_no_link("Create Budget")
        expect(page).to have_no_link("Update Budget")
        expect(page).to have_no_content("Budget Amount")
      end
    end

    # THE RULES ARE NAMED. `pool_rule_label` is the reader Home's expanded row uses, so a rule is
    # named one way on both screens.
    it "lists the rule that fills it" do
      within("[data-holdings-rules]") do
        expect(page).to have_content("1 rule")
        expect(page).to have_content("$400.00")
      end
    end

    # THE START DATE IS PRINTED, because it is the only thing on the card that says WHICH of the
    # user's spending the balance above it covers — anything earlier drained available (§4).
    it "says which spending it counts, from when" do
      within(card) do
        expect(page).to have_content("holds its own money from")
        expect(page).to have_content("spending before then read against what was available")
      end
      expect(find("[data-figure='funded-since']").text).to eq(groceries.funded_since.strftime("%b %-d, %Y"))
    end

    it "draws no goal bar on an envelope" do
      expect(card).to have_no_css("[data-goal-progress]")
    end
  end

  describe "a category with no rule filling it", :aggregate_failures do
    it "says the money arrives by distribution or by hand" do
      cushion = holder("Cushion")
      allocate(cushion, 120)

      visit category_path(cushion)

      expect(card["data-holdings-state"]).to eq("holding")
      expect(card).to have_no_css("[data-holdings-rules]")
      expect(find("[data-figure='no-rules']").text).to include("No rule fills this category")
    end
  end

  # ------------------------------------------------------------------------------------------
  # The goal arm, and the carried inconsistency Task 7 resolved
  # ------------------------------------------------------------------------------------------

  describe "a category saving toward a target", :aggregate_failures do
    it "calls it a goal and states the balance against the target" do
      allocate(holder("Vacation", target_amount: 2_000), 500)

      visit category_path(user.categories.find_by!(name: "Vacation"))

      within(card) do
        expect(page).to have_content("Goal")
        expect(page).to have_no_content("Envelope")
        expect(page).to have_content("$500.00 of $2,000.00")
      end
    end

    it "draws the bar against the target" do
      allocate(holder("Vacation", target_amount: 2_000), 500)

      visit category_path(user.categories.find_by!(name: "Vacation"))

      within("[data-goal-progress]") do
        expect(page).to have_content("25% complete")
        expect(page).to have_content("Target: $2,000.00")
      end
    end

    # THE TARGET'S OTHER CONSEQUENCE, said on the card because the form's hint promises it: a
    # target-bearing category is never swept, whatever its rule mix.
    it "says its money is never swept back" do
      vacation = holder("Vacation", target_amount: 2_000)

      visit category_path(vacation)

      within(card) { expect(page).to have_content("nothing here is ever swept back at the end of a period") }
    end

    # ** THE ANCHOR-DATED GOAL — THE TWO LEVELS ON ONE CARD (fix round 1, MED-2). ** A goal whose
    # rule names a DUE DATE is `HoldingCalculator#dateless_goal?` FALSE, so `HoldingStatus` does not
    # call it `saving`; it is `#saving_toward_a_target?` TRUE, so the heading and the bar are still
    # the goal's. The card therefore heads itself `Goal` and stands `on track` in the same breath,
    # which is two facts rather than a contradiction — what the category IS, and how its schedule is
    # going. The same category is pinned on the impact card (`spec/system/entries/impact_spec.rb`)
    # and on Home's row (`spec/system/home/categories_spec.rb`).
    it "keeps the goal chrome while the standing reads its schedule", :aggregate_failures do
      visit category_path(anchored_goal)

      within(card) do
        expect(page).to have_content("Goal")
        expect(page).to have_no_content("Envelope")
      end
      expect(card).to have_css("[data-goal-progress]")
      within("[data-holdings-status]") do
        expect(page).to have_content("on track")
        expect(page).to have_no_content("of $2,400.00")
      end
    end

    def anchored_goal
      holder("House Deposit", target_amount: 2_400).tap do |house|
        create(
          :budget,
          category: house,
          amount: 300,
          interval_months: 1,
          anchor_date: Date.current + 2.months
        )
        allocate(house, 600)
      end
    end

    # ** THE CARRIED INCONSISTENCY, RESOLVED HERE (Task 7's ruling). ** A goal the user ALSO
    # refills at a rate — the demo's Retirement Supplement — was `Category#savings?` FALSE, so the
    # entry form's impact card drew it as an envelope while Home's row vocabulary called it
    # `saving`. Every rendering asks `HoldingCalculator#saving_toward_a_target?` now, so a
    # rule-bearing goal is a goal on all three screens. Asserted here and on the impact card
    # (spec/system/entries/impact_spec.rb) against the same shape.
    it "is still a goal when a rate rule also fills it" do
      retirement = holder("Retirement", target_amount: 100_000)
      rate(retirement, 150)
      allocate(retirement, 500)

      visit category_path(retirement)

      within(card) do
        expect(page).to have_content("Goal")
        expect(page).to have_no_content("Envelope")
      end
      expect(card).to have_css("[data-goal-progress]")
      # The DISPLAY predicate disagrees, deliberately and on the record rather than on the screen:
      # `Category#savings?` requires no rule, and it survives for the one question it is the right
      # sentence for — which categories are the user's savings, on an index that lists them.
      expect(retirement).not_to be_savings
    end
  end

  # ------------------------------------------------------------------------------------------
  # State 2 — the category holds nothing
  # ------------------------------------------------------------------------------------------

  describe "a category that holds nothing", :aggregate_failures do
    let!(:streaming) { create(:category, :expense, user: user, name: "Streaming") }

    it "says the spending comes out of what's available" do
      visit category_path(streaming)

      expect(card["data-holdings-state"]).to eq("unfunded")
      within(card) do
        expect(page).to have_content("Available")
        expect(page).to have_content("This category doesn't hold money yet.")
        expect(page).to have_content("Its spending comes out of what's available.")
      end
    end

    # THE OTHER DIRECTION, and it is the half that used to be wrong: no balance, no standing and
    # no rule list, because there is nothing holding money for any of them to be about.
    it "claims no balance and no standing for it" do
      visit category_path(streaming)

      expect(card).to have_no_css("[data-figure='balance']")
      expect(card).to have_no_css("[data-holdings-status]")
      expect(card).to have_no_css("[data-goal-progress]")
      within(card) { expect(page).to have_no_content("holds its own money from") }
    end

    # THE SHARPEST HALF. `SuggestionEngine#unfunded_categories` is `reject(&:holder?)` — literally
    # this arm's own population — so this is precisely the shape the panel is most likely to be
    # proposing a rule for, and a rule is this category's only way out.
    it "carries the pointer at the Budget page's proposal" do
      bill(streaming, amount: 180)

      visit category_path(streaming)

      within(card) do
        expect(page).to have_content("the Budget page is proposing")
        expect(page).to have_link("See it on the Budget page", href: budget_page_path(anchor: "suggestions-dated_bill"))
      end
    end

    it "pluralises the pointer when more than one rule is waiting" do
      2.times { bill(streaming, amount: 180) }

      visit category_path(streaming)

      within(card) do
        expect(page).to have_content("proposing 2 rules for this category")
        expect(page).to have_link("See them on the Budget page")
        expect(page).to have_no_link("See it on the Budget page")
      end
    end

    # And with nothing proposed the card is still not a dead end: it makes the offer in the words
    # `entries/_impact`'s honest card already uses for this exact shape.
    it "offers the rule directly when nothing is proposed" do
      visit category_path(streaming)

      expect(card).to have_no_css("[data-suggestion-pointer]")
      within(card) { expect(page).to have_link("Give it a rule on the Budget page", href: budget_page_path) }
    end

    # The holding arm never runs the engine at all — see CategoryBudgetPresenter#suggestions' cost
    # note.
    it "never renders on a category that holds money" do
      groceries = holder("Groceries")
      rate(groceries, 400)

      visit category_path(groceries)

      expect(card["data-holdings-state"]).to eq("holding")
      expect(card).to have_no_css("[data-suggestion-pointer]")
    end
  end

  # AN INCOME CATEGORY HOLDS NOTHING BY THE MODEL'S OWN RULE (`Category#holder?` is `expense? &&
  # …`), so there is no card at all rather than an "Available" arm that would be true and useless.
  describe "an income category", :aggregate_failures do
    it "gets no holdings card" do
      salary = create(:category, :income, user: user, name: "Salary")

      visit category_path(salary)

      expect(page).to have_content("Salary")
      expect(page).to have_no_css("[data-holdings-card]")
    end
  end

  # BOTH SUFFIXES, and each in both directions. This card says how the category stands RIGHT NOW,
  # which is the class of caller `HomeHelper#pool_status_label` documents as owing both — a suffix
  # here and not on Home is two screens describing one category differently on one afternoon.
  describe "the closed-period suffix", :aggregate_failures do
    before do
      rate(holder("Swept"), 400)
      rate(holder("Live"), 400)
      allocate(user.categories.find_by!(name: "Swept"), 60, on: Date.current - 20.days)
      allocate(user.categories.find_by!(name: "Live"), 60)
    end

    it "says which period the money belongs to" do
      visit category_path(user.categories.find_by!(name: "Swept"))

      within(card) { expect(page).to have_content("$60.00 left · last period") }
    end

    it "stays silent on a category funded this period" do
      visit category_path(user.categories.find_by!(name: "Live"))

      within(card) do
        expect(page).to have_content("$60.00 left")
        expect(page).to have_no_content("last period")
      end
    end
  end

  # SPEC §8'S ROUGH EDGE, on a third screen. `travel_to` rather than `update_column`, because the
  # signal is `budgets.updated_at` against the allocation's `created_at` and both have to be
  # written the way the app writes them (see DistributionClock).
  describe "the changed-after-distributing clause", :aggregate_failures do
    include_context "with a rule changed after the money went out"

    before do
      anchor = today + 3.months
      raised = steady = nil

      before_distributing do
        raised = dated("Raised", anchor: anchor)
        steady = dated("Steady", anchor: anchor)
      end

      # Ten dollars against a $1,200 bill three months out leaves both behind, which is the state
      # the clause explains.
      [raised, steady].each { |category| allocate(category, 10) }
      after_distributing { raised.budgets.sole.update!(amount: 1_800) }
    end

    it "says why this category is behind" do
      visit category_path(user.categories.find_by!(name: "Raised"))

      within(card) do
        expect(page).to have_content("behind")
        expect(page).to have_content("you changed a rule here after distributing")
      end
    end

    it "stays silent on a category whose rule nobody touched" do
      visit category_path(user.categories.find_by!(name: "Steady"))

      within(card) do
        expect(page).to have_content("behind")
        expect(page).to have_no_content("you changed a rule here after distributing")
      end
    end
  end

  private

  # A holder carrying a DATED rule. The `behind` state belongs to an accumulating rule — a rate
  # category is `left to spend` however little is in it — so the rate helper above cannot reach it.
  def dated(name, anchor:, amount: 1_200)
    holder(name).tap do |category|
      create(:budget, category: category, amount: amount, interval_months: 6, anchor_date: anchor)
    end
  end

  # A BILL'S SHAPE, straight into `SuggestionEngine`'s dated-bill detector: two payments of the
  # same size a whole month apart, on an item carrying no rule of its own.
  def bill(target, amount:)
    item = create(:item, category: target)
    [2, 1].each { |months| create(:entry, item: item, amount: amount, date: Date.current - months.months) }
  end
end
