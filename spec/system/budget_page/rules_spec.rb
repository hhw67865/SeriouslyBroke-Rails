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

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  def rolling(category, amount:, anchor:, every: 1)
    create(:budget, category: category, amount: amount, interval_months: every, anchor_date: anchor)
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

    # ** §3.4'S ROW (computed-claims Task 3), REPLACING TASK 2'S `$X claimed` / `$X built up`. **
    # The date and the per-period share are the ACCRUING row's second half and belong to the dated
    # rule alone: an anchorless rate rule is never due and accrues toward nothing, so its row carries
    # neither. Both directions on one screen.
    #
    # PLANTED: a $1,200 six-monthly bill anchored three months out on a biweekly grid anchored today.
    # §3.2's `periods_left` counts the boundaries from today through the due date — three months is
    # 89 to 92 days and `floor(days ÷ 14) + 1` is **7** for every one of them — so
    # `planned = 1,200 ÷ 7` = **$171.43**, and one walked period leaves that much built up.
    it "gives the accruing rule a schedule and the rate rule none" do
      within(rule_row("Car Insurance")) do
        expect(page).to have_css(
          "[data-rule-schedule]",
          text: "next due #{(Date.current + 3.months).strftime("%b %-d")} · $171.43 per period"
        )
      end
      within(rule_row("Groceries")) { expect(page).to have_no_css("[data-rule-schedule]") }
    end

    # THE FIGURE, PER SHAPE (§3.4): a rate rule says what it SPENT of its rate, an accruing one what
    # it has BUILT UP of its target. Never both, and never the other one's noun.
    it "reads spent-of-rate on the rate rule and built-up-of-target on the bill" do
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $400.00")
      end
      within(rule_row("Car Insurance")) do
        expect(page).to have_css("[data-rule-figure]", text: "$171.43 built up of $1,200.00")
      end
    end

    # ** THE HEADER IS `Σ its rules' claims` (§3), WHERE A `HoldingStatus` USED TO BE. ** It read
    # `$0.00 left · holds $0.00` — a balance and a state about money that had been MOVED into the
    # category, and nothing moves. Groceries claims its whole unspent rate; Car Insurance claims what
    # it has built up.
    it "heads each category with what its rules claim" do
      within(group("Groceries")) { expect(page).to have_css("[data-category-claim]", text: "$400.00 claimed") }
      within(group("Car Insurance")) { expect(page).to have_css("[data-category-claim]", text: "$171.43 claimed") }
      expect(page).to have_no_content("holds $")
    end
  end

  # ** A DATE THAT HAS GONE BY IS NOT "NEXT" (fix round 1 — MED-1). ** The row above prints
  # `next due Nov 30` for a date ahead; this is the other tense, and it was the finding. A $1,200 bill
  # due ten days ago that nobody has paid keeps its occurrence anchored where it was (§3.2 — the cycle
  # rolls on PAYMENT, not on the calendar), so the row printed `next due` over a date already gone,
  # under a rule the strip was silent about because `#overdue?` also demanded a short fund.
  #
  # PLANTED: `periods_left` floors at 1 for a date already past, so one walked period accrues the
  # whole **$1,200.00** and the per-period share falls to $0.00 — the schedule is the DATE alone,
  # which is exactly the row a user with an unpaid bill needs. Both halves of the row are asserted:
  # the tense on the schedule, and the trouble line that now fires beside it.
  it "puts a rule whose date has passed in the past tense", :aggregate_failures do
    due = Date.current - 10.days
    rolling(holder("Utilities"), amount: 1_200, anchor: due, every: 1)

    visit budget_page_path

    within(rule_row("Utilities")) do
      expect(page).to have_css("[data-rule-schedule]", text: "was due #{due.strftime("%b %-d")}")
      expect(page).to have_no_content("next due")
      expect(page).to have_css("[data-rule-figure]", text: "$1,200.00 built up of $1,200.00")
      expect(page).to have_css("[data-rule-trouble]", text: "overdue · was #{due.strftime("%b %-d")}")
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
        amount: 35,
        category: create(:category, :expense, user: user, name: "Coffee")
      )
      visit budget_page_path
    end

    # THE NAME IS PRINTED ONCE (design review, nits). `budget_rule_name` falls back to the
    # CATEGORY for an item-less rule like this one, so the row's own heading already says
    # "Coffee" — and the reason clause used to say it again, rendering "Coffee · Coffee has no
    # holding date". The clause names the category only where the heading named an ITEM instead;
    # the row as a whole still says both, which is what this example checks.
    #
    # ** THE REASON ITSELF CHANGED WITH THE MODEL (computed-claims spec §6), AND THE OLD ONE WAS
    # THE FALSE HALF. ** It read "isn't holding money yet — nothing fills it", which was true of a
    # distribution: no waterfall reached a category with no funding date. Every rule claims now
    # (`ClaimLedger` counts all of them into `#free`), so the claim is not what is missing — the
    # SPENDING is: `CategoryLedger::ENTRY_CATEGORY_ID` attributes an expense to its category only
    # from `funded_since` on, so this rule claims its full $35 every period while nothing the user
    # spends on Coffee ever comes off it.
    it "keeps it out of the give-way order and names its category in the panel" do
      expect(category_groups).to eq(["Groceries", "Fun Money"])
      expect(page).to have_no_css("[data-category-group='Coffee']")
      within("[data-not-filling-rule='Coffee']") do
        expect(page).to have_content("Coffee")
        expect(page).to have_content("has no claiming date — spending here isn't counted against it")
        expect(page).to have_no_content("Coffee has no claiming date")
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

  # ** TWO GROUPS OF EXAMPLES ARE DELETED HERE (computed-claims Task 3), and both measured a fact
  # about money that had been MOVED into a category (spec §5):
  #
  #   "a category whose period has ended" (2 examples, plus the Home-side cross-screen pin inside the
  #     second) — the ` · last period` suffix. It said "this figure belongs to a period that has
  #     closed and the next distribution will sweep it back". A rate claim is use-it-or-lose-it and
  #     resets at the boundary by definition (§3.1): there is no leftover and nothing to sweep.
  #   "a category whose rule moved after the money did" (2 examples, same shape) —
  #     `DistributionClock` compares a rule's `updated_at` against the moment this period's split was
  #     written, and there is no split.
  #
  # THE CROSS-SCREEN PROPERTY THEY EXISTED FOR SURVIVES, and it is stronger than it was: Home's strip
  # and this page's rule rows print the SAME string about the same rule through ONE helper
  # (`HomeHelper#claim_trouble_label`), rather than through a partial threading two optional suffixes
  # every caller could forget. It is pinned in `spec/system/home/trouble_spec.rb` → "reads the same in
  # the strip as in the period section".

  # The link is in the sidebar, which every signed-in page renders — so it is asserted from two
  # unrelated screens, and its POSITION is asserted too: a rule is neither a report nor a
  # category, and it belongs between the action that spends the money and the ledger that
  # records what was spent.
  describe "the nav", :aggregate_failures do
    it "reaches the page from the categories screen and marks it current" do
      visit categories_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that claim your money")
    end

    it "reaches the page from the entries screen too" do
      visit entries_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that claim your money")
    end

    # A literal list, so neither side is derived from the other. DISTRIBUTE IS GONE FROM IT
    # (computed-claims spec §6) — the screen and its nav item are deleted, and Budget now sits
    # directly after Home because it is the first thing a user does with their money rather than
    # the second.
    it "sits between Home and Entries in the Main section" do
      visit budget_page_path

      expect(page.all("nav a").map { |link| link.text.strip }.first(3))
        .to eq(["Home", "Budget", "Entries"])
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
      expect(page).to have_content("What Groceries claims each period")
      expect(page).to have_field("Rule Amount")
      expect(page).to have_no_select("Pool")
    end

    it "saves the new amount and comes back to the Budget page" do
      fill_in "Rule Amount", with: "425"
      click_button "Update rule"

      expect(page).to have_current_path(budget_page_path)
      within(rule_row("Groceries")) { expect(page).to have_content("$425.00 / period") }
    end
  end
end
