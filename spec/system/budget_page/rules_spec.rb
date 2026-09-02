# frozen_string_literal: true

require "rails_helper"

# The Budget page's top half (spec §8): every active rule, under the category it fills, in the
# order money arrives. `Capybara.exact` is unset in this suite, so every row assertion is scoped
# with `within` — an unscoped `have_content("Groceries")` matches the group heading, the rule name
# and the nav all at once.
RSpec.describe "Budget page rules", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end

  before { sign_in user, scope: :user }

  def group(name) = find("[data-category-group='#{name}']")

  def rule_row(name) = find("[data-rule='#{name}']")

  def category_groups = page.all("[data-category-group]").pluck("data-category-group")

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built here in the pool
  # era, one record shorter.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  def rate(category, amount) = create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)

  def fund(category, amount, on:)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  def rolling(category, amount:, anchor:, every: 1)
    create(:budget, pool: nil, category: category, amount: amount, interval_months: every, anchor_date: anchor)
  end

  describe "the fill order", :aggregate_failures do
    before do
      rate(holder("Groceries", priority: 2), 400)
      rolling(holder("Car Insurance", priority: 1), amount: 1_200, anchor: Date.current + 3.months, every: 6)
      visit budget_page_path
    end

    it "renders each rule under its category, with its amount and basis" do
      within(group("Groceries")) { expect(page).to have_content("$400.00 / period") }
      within(group("Car Insurance")) { expect(page).to have_content("$1,200.00 every 6 months") }
    end

    it "puts the categories in priority order" do
      expect(category_groups).to eq(["Car Insurance", "Groceries"])
      expect(page).to have_no_content("Nothing is in the fill order yet")
    end

    it "states each category's priority position" do
      within(group("Car Insurance")) { expect(page).to have_content("priority 1") }
      within(group("Groceries")) { expect(page).to have_content("priority 2") }
    end

    # The date on the dated rule and NOT on the rate rule, on one screen: an anchorless rule is
    # never due, and BudgetCalculator#due_date answers the end of the period for one.
    it "prints a next date only for the anchored rule" do
      within(rule_row("Car Insurance")) do
        expect(page).to have_content("next #{(Date.current + 3.months).strftime("%b %-d")}")
      end
      within(rule_row("Groceries")) { expect(page).to have_no_content("next") }
    end

    # The row vocabulary is the app's one vocabulary (`pool_status_label`), and the balance is
    # printed only where the label has not already said it — see BudgetPageHelper#pool_balance_clause.
    it "says how each category is doing, and holds only where the label names a bill" do
      within(group("Car Insurance")) { expect(page).to have_content("behind").and have_content("holds $0.00") }
      within(group("Groceries")) { expect(page).to have_content("$0.00 left").and have_no_content("holds") }
    end
  end

  # ── THE ORPHAN BAND IS DELETED OUTRIGHT (two-ledger spec §5, Task 5) ──────────────────────────
  # Its three examples went in plan 3 task 6 when `Pool#account_matches_pool_type` made the fixture
  # unbuildable, and the apparatus they had covered — `BudgetPagePresenter#orphan_rules`,
  # `budget_page/_orphans` and `BudgetPageHelper#budget_rule_reason` — is deleted here with the
  # layer that produced the shape. A rule belongs to a category and every category is in the
  # waterfall, so there is nothing left to be outside the fill order.
  #
  # THE "Nothing is in the fill order yet" STATE SURVIVES AND MEANS SOMETHING ELSE: a rule written
  # before the cutover names only a pool and no group can show it. It is transitional (Task 8) and
  # is pinned on the presenter rather than here, where it would need a fixture nothing in the app
  # can write any more.

  # A RULE WHOSE CATEGORY IS NOT HOLDING MONEY YET (fix round 1, MED-1) — the orphan band's job,
  # re-anchored on the purpose ledger. `Category.in_fill_order` is HOLDERS, so no distribution can
  # reach such a rule and `Category.apply_fill_order` refuses any list naming its category; drawing
  # it as a group would put a priority badge and two arrows on a card whose every use is rejected.
  #
  # THE MIXED PAGE IS THE POINT. A page with only unfillable rules would pass a presenter that
  # simply rendered nothing; this one has two holders that ARE orderable beside one that is not, so
  # the panel and the fill order have to be right about the same screen at the same time.
  #
  # NONE OF THIS EXISTS ON REAL DATA — every writer stamps `funded_since` through `BudgetProposal`
  # — and it is two clicks away once Task 7 ships `funded_since` editing. The rule is planted
  # directly for that reason.
  describe "a rule whose category holds nothing yet", :aggregate_failures do
    before do
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Fun Money", priority: 2), 300)
      create(
        :budget,
        :per_period_rate,
        pool: nil,
        amount: 35,
        category: create(:category, :expense, user: user, name: "Coffee")
      )
      visit budget_page_path
    end

    it "keeps it out of the fill order and names its category in the panel" do
      expect(category_groups).to eq(["Groceries", "Fun Money"])
      expect(page).to have_no_css("[data-category-group='Coffee']")
      within("[data-not-filling-rule='Coffee']") do
        expect(page).to have_content("Coffee isn't holding money yet — nothing fills it")
        expect(page).to have_content("$35.00 / period")
      end
    end

    # THE REFUSAL THE ALIGNMENT KILLED. The endpoint compares the submitted ids against
    # `in_fill_order.with_a_rule`; before the fix the page drew a Coffee card, so its own ▲▼ carried
    # a list containing Coffee and came back "That order didn't match your categories" — a page
    # refusing the order it had just rendered. The message is asserted absent BY ITS OWN WORDS, not
    # merely by the success flash, because a redirect could be right while the flash was wrong.
    it "cannot be refused for the order it rendered itself" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(page).to have_no_content("nothing was changed")
      expect(category_groups).to eq(["Fun Money", "Groceries"])
    end
  end

  describe "a brand-new user", :aggregate_failures do
    before { visit budget_page_path }

    # The first screen every real user meets. The sentence points at the two ways a rule is
    # actually made and promises nothing this page does not yet do.
    it "sees the frame, one sentence and no groups at all" do
      expect(page).to have_content("No funding rules yet")
      expect(page).to have_content("A rule claims part of every period's income for one category")
      expect(page).to have_no_content("Nothing is in the fill order yet")
      expect(page).to have_no_css("[data-category-group]")
      expect(page).to have_no_css("[data-rule]")
    end
  end

  # WHICH PERIOD THE FIGURE BELONGS TO — the suffix `pool_status_label` appends for a rate
  # category whose period has ended, and the one clause the Budget page used to be the only
  # caller in the app to omit.
  #
  # The pair is deliberate and so is its shape: two categories with the SAME rule, the SAME
  # holdings and therefore the same "$400.00 left", differing only in which side of a period
  # boundary the money arrived on. A lone closed-period group would pass against a suffix
  # printed unconditionally.
  #
  # ** THE HOME-SIDE TWIN IS RESTORED (Task 6), and in the other direction. ** It was withdrawn in
  # Task 5 because Home still rendered POOLS and these two categories had no envelope for it to
  # name. Home's rows are categories now, so the pair can be read off BOTH screens on one afternoon
  # — which is the whole point of `shared/_holding_status` and the reason the suffix is threaded off
  # one object rather than passed as a keyword each caller can forget.
  describe "a category whose period has ended", :aggregate_failures do
    before do
      swept = holder("Swept", priority: 1)
      live = holder("Live", priority: 2)
      rate(swept, 400)
      rate(live, 400)
      # Two periods back on a biweekly cadence anchored today, so the rate rule's own period —
      # measured from `last_funded_on`, which is this allocation — closed before today.
      fund(swept, 400, on: Date.current - 21.days)
      fund(live, 400, on: Date.current)
      visit budget_page_path
    end

    it "says which period the figure belongs to, and only where the period has ended" do
      within(group("Swept")) { expect(page).to have_content("$400.00 left · last period") }
      within(group("Live")) do
        expect(page).to have_content("$400.00 left")
        expect(page).to have_no_content("last period")
      end
    end

    # THE CROSS-SCREEN PIN. The same two categories, the same afternoon, read off Home's categories
    # band — and compared to the SAME LITERALS rather than to the Budget page's own rendering, so a
    # label that lost its amount fails here instead of agreeing with itself about nothing.
    it "reads exactly as Home reads for the same categories" do
      visit root_path

      within("[data-holding-name='Swept']") { expect(page).to have_content("$400.00 left · last period") }
      within("[data-holding-name='Live']") do
        expect(page).to have_content("$400.00 left")
        expect(page).to have_no_content("last period")
      end
    end
  end

  # WHY THE CATEGORY IS BEHIND — spec §8's rough edge, on the page it belongs to most.
  #
  # THE PAIR IS THE POINT. Two categories with the same shape of rule, the same distribution and
  # the same `behind` state, differing only in which side of that distribution their rule was last
  # edited on. Split into two examples the negative half would pass against a page that never
  # prints the clause at all.
  #
  # `travel_to` rather than `update_column`: the signal is `budgets.updated_at` against the
  # allocation's `created_at`, and both must be written by the app the way the app writes them —
  # `created_at`, never `date` (a period marker compared to a timestamp is a unit mismatch, see
  # `DistributionClock`).
  #
  # THE CLOCK IS THE SHARED CONTEXT'S, and its `#allocate` writes an `Allocation`, which is what
  # `DistributionClock` reads. Its pool-era `#distribute` twin is DELETED (Task 6) with the
  # `account_ids:` surface that made it necessary.
  #
  # ** THE HOME-SIDE TWIN IS RESTORED HERE TOO (Task 6), for the reason the pair above gives. **
  describe "a category whose rule moved after the money did" do
    include_context "with a rule changed after the money went out"

    before do
      anchor = today + 3.months
      raised = steady = raised_rule = nil

      before_distributing do
        raised = holder("Car Insurance", priority: 1)
        steady = holder("Property Tax", priority: 2)
        raised_rule = rolling(raised, amount: 1_200, anchor: anchor, every: 6)
        rolling(steady, amount: 1_200, anchor: anchor, every: 6)
      end

      # Small enough to leave both behind: the clause explains a `behind` row, so the row has to
      # still be behind.
      [raised, steady].each { |category| allocate(category, 10) }
      after_distributing { raised_rule.update!(amount: 1_800) }

      visit budget_page_path
    end

    it "says so on that group and on no other", :aggregate_failures do
      within(group("Car Insurance")) do
        expect(page).to have_content("behind")
        expect(page).to have_content("you changed a rule here after distributing")
      end
      within(group("Property Tax")) do
        expect(page).to have_content("behind")
        expect(page).to have_no_content("you changed a rule here after distributing")
      end
    end

    # THE CROSS-SCREEN PIN, on the clause most at risk of being threaded on one screen and forgotten
    # on the other — it has shipped that way twice, once between Home and /budget and once between
    # Home's own two bands.
    #
    # THE AMOUNT TRAVELS WITH THE CLAUSE, and it is READ off the page that already rendered it
    # rather than pinned to a second literal: the lag is a function of how many boundaries fall
    # inside a six-month cycle on the calendar the suite happens to run on, which is arithmetic this
    # example does not own. Asserting the bare word "behind" on Home would have been the weaker
    # half of the pair above (`$400.00 left · last period` carries its figure), and a label that
    # lost its amount would have passed.
    #
    # THE TWO SCREENS' CLAUSES AFTER THE STATE DIFFER BY DESIGN — the Budget card adds `· holds $X`
    # and a Home row adds a date (`Group#balance_clause?` against `Row#due_marker?`) — so what is
    # compared is the STATE and its two suffixes, which is exactly what `shared/_holding_status`
    # threads off one object.
    # The two figures are asserted DIFFERENT first: same rule shape and same allocation, but one rule
    # was raised to $1,800 and the other left at $1,200, so a pair of rows both matching one figure
    # would be matching by coincidence.
    it "reads exactly as Home reads for the same categories", :aggregate_failures do
      raised, steady = ["Car Insurance", "Property Tax"].map { |name| behind_figure(group(name)) }
      expect([raised, steady]).to all(match(/\A\$[\d,]+\.\d\d\z/))
      expect(raised).not_to eq(steady)
      visit root_path

      expect(home_row("Car Insurance")).to have_content("behind #{raised} — you changed a rule here after distributing")
      expect(home_row("Property Tax")).to have_content("behind #{steady}")
      expect(home_row("Property Tax")).to have_no_content("you changed a rule here after distributing")
    end

    # The rendered figure, off the group's own status line. `nil` rather than a raise when the
    # label has no amount at all, so the `all(match(...))` above is what reports it.
    def behind_figure(node) = node.text[/behind (\$[\d,]+\.\d\d)/, 1]

    def home_row(name) = find("[data-holding-name='#{name}']")
  end

  # The link is in the sidebar, which every signed-in page renders — so it is asserted from two
  # unrelated screens, and its POSITION is asserted too: a rule is neither a report nor a
  # category, and it belongs between the action that spends the money and the ledger that
  # records what was spent.
  describe "the nav", :aggregate_failures do
    it "reaches the page from the categories screen and marks it current" do
      visit categories_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that fill your categories")
    end

    it "reaches the page from the entries screen too" do
      visit entries_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that fill your categories")
    end

    # A literal list, so neither side is derived from the other.
    it "sits between Distribute and Entries in the Main section" do
      visit budget_page_path

      expect(page.all("nav a").map { |link| link.text.strip }.first(4))
        .to eq(["Home", "Distribute", "Budget", "Entries"])
    end
  end

  # AMENDMENT B's second trap, closed. Before this page existed nothing linked a rule to its form,
  # and the form offered one a picker whose every option makes the record invalid. The link is
  # user-reachable now, so the round trip is asserted end to end.
  describe "editing a rule", :aggregate_failures do
    before do
      rate(holder("Groceries"), 400)
      visit budget_page_path
      within(rule_row("Groceries")) { click_link "Edit" }
    end

    it "opens a form about the category rather than about a pool" do
      expect(page).to have_content("How Groceries gets filled each period")
      expect(page).to have_field("Rule Amount")
      expect(page).to have_no_select("Pool")
    end

    it "saves the new amount and comes back to the Budget page" do
      fill_in "Rule Amount", with: "425"
      click_button "Update Budget"

      expect(page).to have_current_path(budget_page_path)
      within(rule_row("Groceries")) { expect(page).to have_content("$425.00 / period") }
    end
  end
end
