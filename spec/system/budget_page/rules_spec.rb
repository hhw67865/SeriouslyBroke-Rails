# frozen_string_literal: true

require "rails_helper"

# The Budget page's top half (spec §8): every active rule, under the pool it fills, in the order
# money arrives. `Capybara.exact` is unset in this suite, so every row assertion is scoped with
# `within` — an unscoped `have_content("Groceries")` matches the group heading, the rule name and
# the nav all at once.
RSpec.describe "Budget page rules", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def group(name) = find("[data-pool-group='#{name}']")

  # The orphan band is NOT a pool and does not share the pools' selector namespace — it used to,
  # keyed on the literal string "Not in the fill order", so a pool a user actually named that
  # would have collided with it and the fill-order assertion below was plucking a list of pools
  # with a band on the end.
  def orphan_band = find("[data-orphan-group]")

  def rule_row(name) = find("[data-rule='#{name}']")

  def pool_groups = page.all("[data-pool-group]").pluck("data-pool-group")

  def envelope(name, priority: 1)
    create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
  end

  def rate(pool, amount) = create(:pool_budget, :per_period_rate, pool: pool, amount: amount)

  def fund(pool, amount, on:)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def rolling(pool, amount:, anchor:, every: 1)
    create(:pool_budget, pool: pool, amount: amount, interval_months: every, anchor_date: anchor)
  end

  describe "the fill order", :aggregate_failures do
    before do
      rate(envelope("Groceries", priority: 2), 400)
      rolling(envelope("Car Insurance", priority: 1), amount: 1_200, anchor: Date.current + 3.months, every: 6)
      visit budget_page_path
    end

    it "renders each rule under its pool, with its amount and basis" do
      within(group("Groceries")) { expect(page).to have_content("$400.00 / period") }
      within(group("Car Insurance")) { expect(page).to have_content("$1,200.00 every 6 months") }
    end

    it "puts the pools in priority order" do
      expect(pool_groups).to eq(["Car Insurance", "Groceries"])
      expect(page).to have_no_content("Nothing is in the fill order yet")
    end

    it "states each pool's priority position" do
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
    # printed only where the label has not already said it — see BudgetPageHelper::BALANCE_UNSAID.
    it "says how each pool is doing, and holds only where the label names a bill" do
      within(group("Car Insurance")) { expect(page).to have_content("behind").and have_content("holds $0.00") }
      within(group("Groceries")) { expect(page).to have_content("$0.00 left").and have_no_content("holds") }
    end
  end

  # ── THE ORPHAN BAND'S THREE EXAMPLES ARE DELETED (plan 3, task 6) ─────────────────────────
  # "rules no distribution reaches" (two examples) and "a user whose every rule is an orphan"
  # (one) each planted `create(:pool, :savings_pool, account: nil)` — a rule on a pool no account
  # can fund. `Pool#account_matches_pool_type` now requires an account for goals as well as
  # envelopes, and `CHECK ((pool_type = 0) = (account_id IS NULL))` requires it again past the
  # model, so the fixture cannot be built.
  #
  # `budget_page/_orphans`, `BudgetPagePresenter#orphan_rules` and the "Nothing is in the fill
  # order yet" third state are KEPT and now render for nobody. Deleting the whole orphan apparatus
  # is the follow-up this tightening creates; it is named in `Pool::REFUSALS` and in the task 6
  # report. The `#pool_groups` and empty-state examples that survive elsewhere in this file cover
  # the two states a user can still be in.

  describe "a brand-new user", :aggregate_failures do
    before { visit budget_page_path }

    # The first screen every real user meets. The sentence points at the two places a rule is
    # actually made and promises nothing this page does not yet do.
    it "sees the frame, one sentence and no groups at all" do
      expect(page).to have_content("No funding rules yet")
      expect(page).to have_content("A rule claims part of every period's income for one envelope")
      expect(page).to have_no_content("Nothing is in the fill order yet")
      expect(page).to have_no_css("[data-pool-group]")
      expect(page).to have_no_css("[data-orphan-group]")
      expect(page).to have_no_css("[data-rule]")
    end
  end

  # WHICH PERIOD THE FIGURE BELONGS TO — the suffix `pool_status_label` appends for a rate
  # envelope whose period has ended, and the one clause the Budget page used to be the only
  # caller in the app to omit.
  #
  # The pair is deliberate and so is its shape: two envelopes with the SAME rule, the SAME
  # balance and therefore the same "$400.00 left", differing only in which side of a period
  # boundary the money arrived on. A lone closed-period group would pass against a suffix
  # printed unconditionally.
  describe "a pool whose period has ended", :aggregate_failures do
    before do
      swept = envelope("Swept", priority: 1)
      live = envelope("Live", priority: 2)
      rate(swept, 400)
      rate(live, 400)
      # Two periods back on a biweekly cadence anchored today, so the rate rule's own period —
      # measured from `last_funded_on`, which is this movement — closed before today.
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

    # `Σ pools == your bank balance` rests on the two screens agreeing about every pool. Same
    # user, same afternoon, same two envelopes — read off Home and off the Budget page, and the
    # rendered strings compared to a literal rather than to each other.
    it "reads exactly as Home reads for the same pools" do
      visit root_path

      within("[data-pool-name='Swept']") { expect(page).to have_content("$400.00 left · last period") }
      within("[data-pool-name='Live']") do
        expect(page).to have_content("$400.00 left")
        expect(page).to have_no_content("last period")
      end
    end
  end

  # WHY THE ENVELOPE IS BEHIND — spec §8's rough edge, on the page it belongs to most.
  #
  # `_pool_group` passed `period_closed:` and NOT `changed_after_distributing:`, so a `behind`
  # envelope read `behind $X — you changed a rule here after distributing` on Home and a bare
  # `behind $X` here, on the same afternoon: the same defect the pair above closed, in the other
  # direction. And this is the screen that owed the clause most — the rule the user changed is on
  # the row directly beneath the heading, so here the sentence is nearly a caption for what they
  # just did.
  #
  # THE PAIR IS THE POINT, as it is above. Two envelopes with the same shape of rule, the same
  # distribution and the same `behind` state, differing only in which side of that distribution
  # their rule was last edited on. Split into two examples the negative half would pass against a
  # page that never prints the clause at all.
  #
  # `travel_to` rather than `update_column`: the signal is `budgets.updated_at` against the
  # movement's `created_at`, and both must be written by the app the way the app writes them —
  # `created_at`, never `date` (a period marker compared to a timestamp is a unit mismatch, see
  # `DistributionClock`).
  #
  # THE CLOCK IS THE SHARED CONTEXT'S (plan 3, task 6). This block hand-rolled the three-moment
  # recipe, as three other screens did, and two of the four copies drifted into the same wall-clock
  # flake — so `today`, the three travelled moments and the movement's own creation live in
  # `spec/support/changed_after_distributing_context.rb` and the assertions stay here.
  describe "an envelope whose rule moved after the money did" do
    include_context "with a rule changed after the money went out"

    before do
      deposit(2_000)
      anchor = today + 3.months
      raised = steady = raised_rule = nil

      before_distributing do
        raised = envelope("Car Insurance", priority: 1)
        steady = envelope("Property Tax", priority: 2)
        raised_rule = rolling(raised, amount: 1_200, anchor: anchor, every: 6)
        rolling(steady, amount: 1_200, anchor: anchor, every: 6)
      end

      # Small enough to leave both behind: the clause explains a `behind` row, so the row has to
      # still be behind.
      [raised, steady].each { |pool| distribute(pool, 10) }
      after_distributing { raised_rule.update!(amount: 1_800) }

      visit budget_page_path
    end

    def deposit(amount)
      category = create(:category, :income, user: user, pool: checking, name: "Pay")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
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

    # `Σ pools == your bank balance` rests on the two screens agreeing about every pool, and the
    # clause is part of what they have to agree about. Same user, same afternoon, same two
    # envelopes — read off /budget and off Home, each compared to the literal rather than to the
    # other.
    it "reads exactly as Home reads for the same pools", :aggregate_failures do
      visit root_path

      expect(find("[data-pool-name='Car Insurance']"))
        .to have_content("you changed a rule here after distributing")
      expect(find("[data-pool-name='Property Tax']"))
        .to have_no_content("you changed a rule here after distributing")
    end
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
      expect(page).to have_content("The rules that fill your envelopes")
    end

    it "reaches the page from the entries screen too" do
      visit entries_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that fill your envelopes")
    end

    # A literal list, so neither side is derived from the other.
    it "sits between Distribute and Entries in the Main section" do
      visit budget_page_path

      expect(page.all("nav a").map { |link| link.text.strip }.first(4))
        .to eq(["Home", "Distribute", "Budget", "Entries"])
    end
  end

  # AMENDMENT B's second trap, closed. Before this page existed nothing linked a pool-mode rule to
  # its form, and the form offered one a CATEGORY picker whose every option makes the record
  # invalid. The link is user-reachable now, so the round trip is asserted end to end.
  describe "editing a rule", :aggregate_failures do
    before do
      rate(envelope("Groceries"), 400)
      visit budget_page_path
      within(rule_row("Groceries")) { click_link "Edit" }
    end

    it "opens a form about the pool rather than about a category" do
      expect(page).to have_content("How Groceries gets filled each period")
      expect(page).to have_field("Rule Amount")
      expect(page).to have_no_select("Category")
    end

    it "saves the new amount and comes back to the Budget page" do
      fill_in "Rule Amount", with: "425"
      click_button "Update Budget"

      expect(page).to have_current_path(budget_page_path)
      within(rule_row("Groceries")) { expect(page).to have_content("$425.00 / period") }
    end
  end
end
