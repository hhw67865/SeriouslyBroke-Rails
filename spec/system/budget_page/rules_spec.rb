# frozen_string_literal: true

require "rails_helper"

# ** WHAT ONE RULE SAYS ABOUT ITSELF, INSIDE THE CATEGORY THAT IS OPEN (two-shapes spec §4). **
# `Capybara.exact` is unset in this suite, so every row assertion is scoped with `within` — an
# unscoped `have_content("Groceries")` matches the row's name, the rule's name and the nav at once.
#
# ** THIS FILE SPLIT IN THREE WHEN THE PAGE DID (this task), and the successors are named here so a
# reader looking for a deleted example finds it:
#
#   `list_spec.rb`  — the LIST: every expense category, give-way order, the rule count, the type
#                     dots, `$X claimed`, the suggestion badge, the rule-less rows, the empty state
#                     and the 375px pin. The old "the fill order" and "the type overview" groups.
#   `open_spec.rb`  — OPENING one: one at a time, the `?open=` parameter without JavaScript, the
#                     panel's memory, only that category's suggestions, and the "+ New rule for
#                     <category>" button.
#   `tiles_spec.rb` — the three tiles (successor of `structural_check_spec.rb`), which is where the
#                     type overview's three figures went.
#
# WHAT STAYS HERE is the RULES TABLE itself — the sentence a rule says — plus the nav and the edit
# round trip, because both are about a rule rather than about the list.
RSpec.describe "Budget page rules", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end

  before { sign_in user, scope: :user }

  def group(name) = find("[data-category-group='#{name}']")

  def rule_row(name) = find("[data-rule='#{name}']")

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built here in the pool
  # era, one record shorter.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  # `type:` DEFAULTS TO `usage`, THE COLUMN'S OWN DEFAULT (rules-own-the-budget spec §6 step 3), so
  # every fixture written before rules had a type keeps the label the migration would have given it.
  def rate(category, amount, type: :usage)
    create(:budget, :per_period_rate, category: category, amount: amount, rule_type: type)
  end

  def rolling(category, amount:, anchor:, every: 1)
    create(:budget, category: category, amount: amount, interval_months: every, anchor_date: anchor)
  end

  # A ONE-TIME BILL ON AN ITEM. `created_at` IS PLANTED TWO MONTHS BACK, because a rule accrues from
  # the LATER of its category's funding date and its OWN birth: a rule created at the wall clock
  # walks only today's period, and a receipt dated before it moves nothing at all
  # (`ClaimCalculator#accrual_start`).
  # AN ITEM-BACKED ONE-OFF ALREADY PAST ITS DATE — the whole fixture the paid example needs, and the
  # state it starts in.
  def overdue_one_off(name)
    create(:item, category: holder("Utilities"), name: name)
      .tap { |item| one_off(item, amount: 600, due: Date.current - 10.days) }
  end

  def one_off(item, amount:, due:)
    create(
      :budget,
      :one_time,
      category: item.category,
      item: item,
      amount: amount,
      anchor_date: due,
      created_at: 2.months.ago
    )
  end

  # A ONE-TIME BILL ON AN ITEM. `created_at` IS PLANTED TWO MONTHS BACK, because a rule accrues from
  # the LATER of its category's funding date and its OWN birth: a rule created at the wall clock
  # walks only today's period and a receipt dated before it moves nothing at all
  # (`ClaimCalculator#accrual_start`).
  # AN ITEM-BACKED ONE-OFF ALREADY PAST ITS DATE — the whole fixture the paid example needs, and the
  # state it starts in.
  def overdue_one_off(name)
    create(:item, category: holder("Utilities"), name: name)
      .tap { |item| one_off(item, amount: 600, due: Date.current - 10.days) }
  end

  def one_off(item, amount:, due:)
    create(
      :budget,
      :one_time,
      category: item.category,
      item: item,
      amount: amount,
      anchor_date: due,
      created_at: 2.months.ago
    )
  end

  # ** ONE CATEGORY IS OPEN AT A TIME (§4), so a rule's row is reached through its category. ** The
  # closed panels are rendered and `hidden`, which is exactly what Capybara refuses to see; `?open=`
  # is the same parameter the chevron writes.
  def open_category(name) = visit(budget_page_path(open: user.categories.find_by!(name: name).id))

  describe "the rules table", :aggregate_failures do
    before do
      rate(holder("Groceries", priority: 2), 400)
      rolling(holder("Car Insurance", priority: 1), amount: 1_200, anchor: Date.current + 3.months, every: 6)
    end

    # ** THE SHAPE CLAUSE REPLACED THE STICKER (§4). ** The row printed `$400.00 / period` and
    # `$1,200.00 every 6 months` — `BudgetPageHelper#budget_rule_amount`, deleted with the group
    # card, which on a dated rule said the target a second time inside a row already showing it.
    # `HomeHelper#shape_words` says the type and the schedule and no money at all, which is the one
    # thing the row was missing and is the SAME clause Home prints about the same rule.
    it "says each rule's type and schedule, and no second copy of its amount" do
      open_category("Groceries")
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-shape]", text: "usage · a period")
        expect(page).to have_no_content("/ period")
      end

      open_category("Car Insurance")
      within(rule_row("Car Insurance")) do
        # `usage` IS THE COLUMN'S DEFAULT and the fixture leaves it there — the point of the clause
        # is the SCHEDULE beside the type, and a bill would say the same sentence with one word
        # changed. The three types' own colours are `list_spec`'s dots.
        expect(page).to have_css("[data-rule-shape]", text: "usage · every 6 months")
      end
    end

    # ** THE `when` CLAUSE, PER SHAPE (§3/§4) — `HomeHelper#when_words`, ONE spelling for three
    # screens. ** It was `#claim_schedule`'s `next due Nov 30 · $171.43 per period`; the collapsed
    # helper says the date and the contribution with a leading plus, which is what tells a share
    # from a total. A rate rule says when it RESETS, which the old helper had no answer for at all.
    #
    # PLANTED: a $1,200 six-monthly bill anchored three months out on a biweekly grid anchored
    # today. §3.2's `periods_left` counts the boundaries from today through the due date — three
    # months is 89 to 92 days and `floor(days ÷ 14) + 1` is **7** for every one of them — so
    # `planned = 1,200 ÷ 7` = **$171.43**, and one walked period leaves that much built up.
    it "dates the accruing rule and resets the rate rule" do
      open_category("Car Insurance")
      within(rule_row("Car Insurance")) do
        expect(page).to have_css("[data-rule-when]", text: "#{(Date.current + 3.months).strftime("%b %-d")} · +$171.43")
      end

      open_category("Groceries")
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-when]", text: "resets")
      end
    end

    # ** THE FIGURE, PER SHAPE, AND IN ONE VOCABULARY (this task's carry (b)). ** It read
    # `$171.43 built up of $1,200.00` here and `$171.43 of $1,200.00` on Home — two helpers, one
    # fact. `#figure_words` is what all three screens say now, and the noun is not the caller's to
    # choose: a row printing "spent" over a target's running total would be the money screen's
    # oldest lie.
    it "reads what each rule has of what it needs" do
      open_category("Groceries")
      within(rule_row("Groceries")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $400.00")
        expect(page).to have_no_content("built up")
      end

      open_category("Car Insurance")
      within(rule_row("Car Insurance")) do
        expect(page).to have_css("[data-rule-figure]", text: "$171.43 of $1,200.00")
      end
    end

    # ** THE STRIPE IS THE RULE'S TYPE AND THE BAR IS ITS STATE (§4), where a grey "Bill" chip used
    # to be. ** The chip said the type in words on a row whose shape clause now leads with it; the
    # stripe says it in the colour the list's dots and Home's rows use, so the same rule is the same
    # colour on every screen.
    it "carries a bar in the state the row is in" do
      open_category("Car Insurance")

      expect(find("[data-rule='Car Insurance'] [data-rule-bar]")["data-rule-bar-state"]).to eq("normal")
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

    open_category("Utilities")

    within(rule_row("Utilities")) do
      expect(page).to have_css("[data-rule-when]", text: "overdue · was #{due.strftime("%b %-d")}")
      expect(page).to have_no_content("next due")
      expect(page).to have_css("[data-rule-figure]", text: "$1,200.00 of $1,200.00")
    end
  end

  # ** AND A ONE-OFF THAT HAS BEEN PAID SAYS SO, WHERE IT USED TO SAY THE OPPOSITE (this task's
  # carry (a)). ** A one-time bill's occurrence never rolls, so on the day after the money went out
  # this row read `overdue · was <date>` for ever — the worst sentence the vocabulary has, about a
  # bill that had been paid. Both directions on one fixture: the same rule before and after the
  # payment, which is what says the arm fires on the FULFILMENT and not on the date.
  it "calls a paid one-off paid, with the day it was paid on", :aggregate_failures do
    paid_on = Date.current - 2.days
    water = overdue_one_off("Water")

    open_category("Utilities")
    within(rule_row("Water")) { expect(page).to have_css("[data-rule-when]", text: "overdue · was") }

    create(:entry, item: water, amount: 600, date: paid_on)
    open_category("Utilities")
    # THE DATE HAS NOT MOVED — a one-time rule's occurrence never rolls, which is what makes this
    # sentence the FULFILMENT's rather than the calendar's, and what left the old reading with
    # nothing to stop it saying "overdue" for ever (`claim_calculator_spec` pins the anchor itself).
    within(rule_row("Water")) do
      expect(page).to have_css("[data-rule-when]", text: "paid #{paid_on.strftime("%b %-d")}")
        .and have_no_content("overdue")
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

  # ** FOUR GROUPS MOVED TO `list_spec.rb` WITH THE LIST THEY WERE ABOUT (this task). ** "the fill
  # order"'s ordering and header examples, "a rule whose category holds nothing yet", "a brand-new
  # user" and "the type overview" are all statements about which ROWS the page draws and in what
  # order — which is the list's subject, not a rule's. Two of them changed meaning on the way and
  # the successor says how: a category that holds nothing has a ROW now (the "not filling" band it
  # was kept out of is deleted), and a brand-new user with a category is no longer empty at all.
  #
  # THE TYPE OVERVIEW'S THREE FIGURES ARE IN `tiles_spec.rb`, on the tile that replaced the line,
  # and the 375px pin is in `list_spec.rb`, which is where the widest line on this page now is.

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
      open_category("Groceries")
      within(rule_row("Groceries")) { click_link "Edit" }
    end

    it "opens a form about the category rather than about a pool" do
      # ** THE FORM IS ITS OWN PAGE AND IT IS TITLED BY THE RULE (two-shapes spec §5). ** It read
      # "What Groceries claims each period" — the subtitle of the picker-era form — and the page now
      # names the rule it opened on, with the category in the breadcrumb above it.
      expect(page).to have_content("Groceries — edit rule")
      expect(page).to have_field("Amount")
      expect(page).to have_no_select("Pool")
    end

    it "saves the new amount and comes back to the Budget page" do
      fill_in "Amount", with: "425"
      click_button "Update rule"

      expect(page).to have_current_path(budget_page_path)
      # THE ROW READS THE CLAIM, where it used to read the sticker (`budget_rule_amount`, deleted
      # with the group card): on an untouched per-period rule the denominator IS the amount just
      # written, which is the same claim about the same write off the figure the page prints. The
      # redirect carries no `open`, so the panel is asked for again.
      open_category("Groceries")
      within(rule_row("Groceries")) { expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $425.00") }
    end
  end
end
