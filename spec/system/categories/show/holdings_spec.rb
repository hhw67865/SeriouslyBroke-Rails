# frozen_string_literal: true

require "rails_helper"

# THE CATEGORIES PAGE'S HOLDINGS CARD — two states, each asserted in both directions. Converted onto
# computed claims by Task 4; the file kept its name because the card kept its route and its hooks.
#
# ** EVERY FIGURE IN THIS FILE IS A CLAIM NOW, AND NOT A HOLDING (computed-claims spec §2, §5). **
# The card read a `HoldingCalculator#balance` — allocations in, less allocations out, less the
# spending attributed to the category — and stood a `HoldingStatus` beside it. Nothing moves on the
# purpose side any more, so every `allocate(...)` in this file is gone and the money the fixtures
# used to move is written the way the model actually puts it there: a rule that accrues. Every figure
# below is a PLANTED LITERAL re-derived from §3's formulas with the working beside it.
#
# ── DELETED RATHER THAN CONVERTED. Each asserted a fact about money that had been MOVED, and nothing
# moves:
#
#   * "says its money is never swept back" — the ` · never swept` promise named a sweep at the period
#     boundary. There is no sweep because there is nothing to sweep: a rate claim RESETS to the rate
#     at every boundary by its own definition (§3.1) and no money changes hands to do it. The
#     consequence the sentence was really about — that a target makes a category's undated rules
#     CARRY what they build up instead of losing it — survives structurally, in
#     `ClaimCalculator#shape`, and is pinned by "keeps a goal's built-up against its target" below
#     and by the form's own hint in `categories/new/form_spec.rb`.
#   * "keeps the goal chrome while the standing reads its schedule" — the `Standing` row, its
#     `shared/_holding_status` partial and the whole two-level goal classification it belonged to are
#     deleted with `HoldingStatus`. The card has no state word left to disagree with its heading:
#     what a rule is doing is §3.4's own row, which is a figure and a schedule rather than one of
#     seven adjectives. "gives an accruing rule its schedule and a rate rule none" carries the fact
#     the example was really pinning — that a goal with a due date is read by its schedule.
#   * the whole "a category that is not holding but still has money in it" group (3 examples) — it
#     planted allocations past `Category#money_may_not_be_stranded` with `update_column` and asserted
#     the card named the money anyway. Nothing is ever MOVED into a category now, so a cleared
#     funding date leaves nothing behind and the fixture cannot be built by any means at all — the
#     state is unplantable rather than merely unreachable, which is why the `stranded?` arm is
#     deleted instead of left untested. "says its spending comes straight out of what's free to
#     spend" carries what remains true of a non-holder.
#   * the "closed-period suffix" pair — ` · last period` named a leftover physically sitting in an
#     envelope until a distribution moved it. §3.1's claim resets at the boundary; there is no
#     leftover and no period for one to belong to.
#   * the "changed-after-distributing clause" pair, and the `spec/support/changed_after_distributing_context.rb`
#     include that built them — `DistributionClock` compared a rule's `updated_at` against the moment
#     a period's split was written, and there is no split. A rule change now moves the claim on the
#     next render with nothing to explain, which is the whole of what the computed model buys.
#
# ── CARRIED, WITH THE FIGURES RE-DERIVED: the two arms and their `data-holdings-state` stamp, the
# goal heading and its bar (the same 25%, now claim over target), the rule list, the funding date,
# the suggestion pointer's three examples, and the income category's absence.
#
# `Capybara.exact` is unset in this suite and this page is full of chrome that matches substrings
# (the sidebar's "Budget" link, the summary card's own sentence about the spending, the category's
# own name in three places), so every assertion is scoped to `[data-holdings-card]` and every
# positive is paired with a negative.
RSpec.describe "Categories Show - Holdings card", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST for income to land in
  # (`Category#income_must_land_in_an_account`), and for the category factory's own `pool` default.
  # Nothing on this card reads it.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  before { sign_in user, scope: :user }

  def card = find("[data-holdings-card]")

  def rule_row(label) = find("[data-holdings-rule='#{label}']")

  # A category whose rules claim its money: an expense category with a `funded_since`, a year back so
  # nothing in a fixture has to say a date twice and every entry dated "today" counts against it.
  def holder(name, **attributes)
    create(:category, :expense, :funded, user: user, name: name, **attributes)
  end

  # §3.1'S SHAPE — use-it-or-lose-it, no anchor, no item, so its lane is the whole category.
  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  # §3.2'S SHAPE — accrues toward its own amount by the catch-up formula.
  def dated(category, amount:, anchor:, every: 6, item: nil)
    create(:budget, category: category, amount: amount, interval_months: every, anchor_date: anchor, item: item)
  end

  def spend(category, amount, on: Date.current, item: nil)
    create(:entry, item: item || create(:item, category: category), amount: amount, date: on)
  end

  # ------------------------------------------------------------------------------------------
  # State 1 — the category's rules claim its money
  # ------------------------------------------------------------------------------------------

  describe "a category whose rules claim its money", :aggregate_failures do
    let!(:groceries) { holder("Groceries") }

    before do
      rate(groceries, 400)
      visit category_path(groceries)
    end

    # PLANTED: a $400 per-period rate rule with nothing spent. §3.1 is
    # `max(0, rate + Σ adjustments − spent)` = `max(0, 400 + 0 − 0)` = **$400.00**, which is the whole
    # of the category's claim because it is its only rule.
    it "names what it is, prints what it claims and links to the Budget page" do
      expect(card["data-holdings-state"]).to eq("holding")
      within(card) do
        expect(page).to have_content("Envelope")
        expect(page).to have_no_content("Goal")
        expect(page).to have_link("Rules on the Budget page", href: budget_page_path)
      end
      expect(find("[data-figure='claim']").text).to eq("$400.00")
    end

    # NO EDITOR, and the negative is the point: what a category claims is decided by its rules, and
    # a rule is written on /budget.
    it "offers no editor of its own" do
      within(card) do
        expect(page).to have_no_link("Create rule")
        expect(page).to have_no_link("Update rule")
        expect(page).to have_no_content("Budget Amount")
      end
    end

    # ** THE COPY THE MOVED-MONEY MODEL LEFT BEHIND, ASSERTED ABSENT. ** Each of these sentences was
    # rendered by this card and each is now false — there is no `available` to read against, no
    # sweep at a period's end, and no distribution that puts money here.
    it "says nothing about available, sweeping or distributing" do
      within(card) do
        expect(page).to have_no_content("available")
        expect(page).to have_no_content("swept")
        expect(page).to have_no_content("distribute")
        expect(page).to have_content("Nothing was moved here")
      end
    end

    # THE START DATE IS PRINTED, because it is the only thing on the card that says which periods and
    # which receipts the figure above it is made of: it is `ClaimCalculator#accrual_start`'s first
    # term — the period the accrual walk opens in — and the day `Entry.draining` starts attributing
    # this category's spending to its rules. Anything earlier is in neither sum.
    it "says which spending and which periods it counts, from when" do
      within(card) { expect(page).to have_content("Claiming since") }
      expect(find("[data-figure='funded-since']").text).to eq(groceries.funded_since.strftime("%b %-d, %Y"))
    end

    it "draws no fund bar on an envelope" do
      expect(card).to have_no_css("[data-building-progress]")
    end
  end

  # ------------------------------------------------------------------------------------------
  # §3.4's row, per rule — the same sentences the Budget page and Home print about one rule
  # ------------------------------------------------------------------------------------------

  describe "the row each rule gets", :aggregate_failures do
    # PLANTED: $310 spent this period against a $400 per-period rate. The figure is `spent of rate`
    # verbatim, and the claim is `max(0, 400 − 310)` = **$90.00**. `over?` reads the pre-clamp figure
    # (+$90), so nothing is red and there is no trouble line.
    it "reads spent-of-rate on a rate rule, with no schedule and no trouble" do
      groceries = holder("Groceries")
      rate(groceries, 400)
      spend(groceries, 310)

      visit category_path(groceries)

      expect(find("[data-figure='claim']").text).to eq("$90.00")
      within(rule_row("Per period")) do
        expect(page).to have_css("[data-rule-figure]", text: "$310.00 of $400.00")
        expect(page).to have_no_css("[data-rule-schedule]")
        expect(page).to have_no_css("[data-rule-trouble]")
      end
    end

    # PLANTED: $450 spent against the same $400 rate. The pre-clamp figure is `400 − 450` = **−$50**,
    # which is what makes the row "over" and what the trouble label prints — the CLAIM is clamped to
    # **$0.00**, so a figure taken from the claim would read "over by $0.00" on every overspend
    # (`HomeHelper#claim_trouble_label`'s own note).
    it "puts an overspent rate rule in the red with the excess named" do
      groceries = holder("Groceries")
      rate(groceries, 400)
      spend(groceries, 450)

      visit category_path(groceries)

      expect(find("[data-figure='claim']").text).to eq("$0.00")
      within(rule_row("Per period")) do
        expect(page).to have_css("[data-rule-figure]", text: "$450.00 of $400.00")
        expect(page).to have_css("[data-rule-trouble]", text: "over by $50.00")
      end
    end

    # PLANTED: a $1,200 six-monthly bill anchored three months out, on a biweekly grid anchored today.
    # The rule is written today, so §3.2's walk opens in the current period and visits exactly one
    # (`accrual_start` is the LATER of the category's funding date and the rule's own birthday).
    # `periods_left` counts the boundaries from this period's open through the due date — three
    # months is 89 to 92 days and `floor(days ÷ 14) + 1` is **7** for every one of them — so
    # `planned = 1,200 ÷ 7` = **$171.43**, and one walked period leaves exactly that built up.
    # The same figure is pinned on the Budget page in `budget_page/rules_spec.rb`.
    it "gives an accruing rule its figure and its schedule" do
      insurance = holder("Car Insurance")
      dated(insurance, amount: 1_200, anchor: Date.current + 3.months)

      visit category_path(insurance)

      expect(find("[data-figure='claim']").text).to eq("$171.43")
      within(rule_row("Every 6 months")) { expect_the_accruing_row(Date.current + 3.months) }
    end

    # The row's three assertions, lifted out of the example above so it stays inside the length its
    # neighbours keep. The figure and the schedule are §3.4's two halves and the absent trouble is
    # the third fact: a fund on course is not a thing that needs a human (§4).
    def expect_the_accruing_row(due_on)
      expect(page).to have_css("[data-rule-figure]", text: "$171.43 built up of $1,200.00")
      expect(page).to have_css(
        "[data-rule-schedule]",
        text: "next due #{due_on.strftime("%b %-d")} · $171.43 per period"
      )
      expect(page).to have_no_css("[data-rule-trouble]")
    end

    # ** A DATE THAT HAS GONE BY IS NOT "NEXT". ** The cycle rolls on PAYMENT rather than on the
    # calendar (§3.2), so an occurrence nobody settled stays where it was anchored and the row reads
    # overdue instead of silently re-aiming a month out.
    #
    # PLANTED: `periods_left` floors at 1 for a date already past, so the one walked period accrues
    # the whole **$1,200.00** — the fund is FULL, which is the ordinary shape of an unpaid bill, not
    # the exception — and the per-period share falls to $0.00, so the schedule is displaced entirely
    # by the trouble line beside it.
    it "puts a rule whose date has passed in the past tense, with the trouble line" do
      due = Date.current - 10.days
      utilities = holder("Utilities")
      dated(utilities, amount: 1_200, anchor: due, every: 1)

      visit category_path(utilities)

      expect(find("[data-figure='claim']").text).to eq("$1,200.00")
      within(rule_row("Monthly")) do
        expect(page).to have_css("[data-rule-figure]", text: "$1,200.00 built up of $1,200.00")
        expect(page).to have_css("[data-rule-trouble]", text: "overdue · was #{due.strftime("%b %-d")}")
        expect(page).to have_no_content("next due")
      end
    end
  end

  # ** A LINE PER RULE, AND THE CARD'S FIGURE IS THEIR SUM (§3.4; Task 3's ruling for Home). ** §3.4's
  # sentences are per RULE and `Category#claim` is a SUM, so a category carrying a rate rule beside an
  # item-backed bill cannot honestly print one figure: the two are denominated in different things —
  # one in this period's spending against a rate, the other in a running total against a target.
  #
  # THE ITEM ON THE BILL IS WHAT MAKES THE LANES DISJOINT (§3.1's partition, and
  # `Budget#category_may_hold_one_item_less_rule`): the rate rule names no item, so its lane is the
  # category MINUS the items that carry their own rule.
  describe "a category with two rules", :aggregate_failures do
    let!(:home) { holder("Home") }

    before do
      rate(home, 400)
      dated(home, amount: 1_200, anchor: Date.current + 3.months, item: create(:item, category: home, name: "Insurance"))
      visit category_path(home)
    end

    # PLANTED: $400.00 (the untouched rate, §3.1) + $171.43 (one period of `1,200 ÷ 7`, §3.2 — the
    # working is on "gives an accruing rule its figure and its schedule" above) = **$571.43**.
    it "heads the card with the sum of its rules' claims" do
      expect(find("[data-figure='claim']").text).to eq("$571.43")
      within("[data-holdings-rules]") { expect(page).to have_content("2 rules") }
    end

    # EACH ROW IN ITS OWN SHAPE'S WORDS, and never the other's noun: a rate row must not print
    # "built up" over money that carries nothing, and a fund's running total must not read as money
    # to spend. `pool_rule_label` names the item-backed rule by its item and the item-less one by its
    # cadence, which is the app's one answer to what a rule is called.
    it "says each rule's own sentence, in its own row" do
      within(rule_row("Insurance")) do
        expect(page).to have_css("[data-rule-figure]", text: "$171.43 built up of $1,200.00")
      end
      within(rule_row("Per period")) do
        expect(page).to have_css("[data-rule-figure]", text: "$0.00 of $400.00")
        expect(page).to have_no_content("built up")
      end
    end
  end

  # ------------------------------------------------------------------------------------------
  # The fund arm
  # ------------------------------------------------------------------------------------------

  describe "a category whose money builds up", :aggregate_failures do
    # ** A FUND IS A BUILDING RULE (rules-own-the-budget spec §5/§7), AND THE CATEGORY NAMES NOTHING.
    # ** `ClaimCalculator#shape` reads `:building` off the RULE's own `carries_over` — the branch
    # that makes money CARRY rather than reset — and `budgets.target_amount` is where it stops. This
    # card's heading and its bar read `Category#building_rule` now, so the fixture stops writing the
    # category's copy of the figure: a fixture that still wrote it would let a reader that had
    # quietly stayed behind go on passing, and Task 4 drops the column in any case.
    def fund(name, target:, rate_amount:)
      holder(name).tap do |category|
        create(:budget, :capped, category: category, amount: rate_amount, target_amount: target)
      end
    end

    # PLANTED: a $500-per-period rule on a $2,000 goal, funded a year back but written today, so the
    # walk visits one period. §3.2's dateless branch plans `min(rate, gap)` = `min(500, 2,000)` =
    # **$500.00**, nothing is spent, so `built_up` = $500.00 and the claim is that. The bar is
    # `(500 ÷ 2,000 × 100).round` = **25** — the same 25% the moved-money version of this example
    # asserted over a $500 allocation, which is the point of keeping the figure.
    it "calls it a fund and states its built-up against the rule's target" do
      visit category_path(fund("Vacation", target: 2_000, rate_amount: 500))

      within(card) { expect(page).to have_content("Fund") }
      expect(card).to have_no_content("Envelope")
      expect(card).to have_no_content("Goal")
      expect(find("[data-figure='claim']").text).to eq("$500.00")
      within("[data-building-progress]") do
        expect(page).to have_content("25% complete")
        expect(page).to have_content("Target: $2,000.00")
      end
    end

    # ** AN UNCAPPED FUND IS STILL A FUND, AND IT DRAWS NO TRACK (rules-own-the-budget spec §2.1 row
    # 2; §5). ** The old classifier was a question about a FIGURE, so an emergency fund that names
    # none read as an envelope on this card — the wrong heading over money that carries. The heading
    # is a question about the SHAPE now; what the missing figure takes away is the BAR, because there
    # is nothing for one to be a fraction of. Both halves asserted, so a fix that printed a full or
    # an empty track against $0.00 would fail here.
    #
    # PLANTED: a $500-a-period uncapped building rule, funded a year back but written today, so the
    # walk visits one period and plans its plain rate — `built_up` = **$500.00**, with no `gap` to
    # bound it.
    it "calls an uncapped fund a fund and draws no track at all" do
      emergency = holder("Emergency")
      create(:budget, :building, category: emergency, amount: 500)

      visit category_path(emergency)

      within(card) do
        expect(page).to have_content("Fund")
        expect(page).to have_no_content("Envelope")
      end
      expect(find("[data-figure='claim']").text).to eq("$500.00")
      expect(page).to have_no_css("[data-building-progress]")
    end

    # ** THE ROW READS THE GOAL AS A FUND, NEVER AS MONEY TO SPEND. ** The figure is
    # `built up of target` and the schedule is the rate the goal is filling at; a dateless goal has
    # no due date, so `claim_schedule` drops that half and prints the per-period share alone.
    it "keeps a fund's built-up against its target, with the rate it fills at" do
      visit category_path(fund("Vacation", target: 2_000, rate_amount: 500))

      within(rule_row("Per period")) do
        expect(page).to have_css("[data-rule-figure]", text: "$500.00 built up of $2,000.00")
        expect(page).to have_css("[data-rule-schedule]", text: "+$500.00 per period")
        expect(page).to have_no_content("due")
      end
    end

    # ** THE CARRIED INCONSISTENCY, NOW RESOLVED STRUCTURALLY. ** A goal the user ALSO refills at a
    # rate — the demo's Retirement Supplement — was `Category#savings?` FALSE, because that predicate
    # additionally required the category to carry NO rule; the entry form's impact card therefore
    # drew it as an envelope while Home called it saving. Every claim comes from a rule (§3.3), so
    # "a goal is a category with no rule" had become a description of a goal that does not work, and
    # the successor reads the rule outright: `Category#building_rule` is what all three screens ask,
    # so the two readings that could disagree are one reading.
    #
    # PLANTED: `min(rate, gap)` = `min(150, 100,000)` = **$150.00** after one period, which is
    # `(150 ÷ 100,000 × 100).round` = **0**% — a bar drawn at zero, which is exactly the row that
    # would have been unassertable if the percentage rode on the fill rather than on the track.
    it "is still a fund when a rate fills it" do
      retirement = fund("Retirement", target: 100_000, rate_amount: 150)

      visit category_path(retirement)

      within(card) do
        expect(page).to have_content("Fund")
        expect(page).to have_no_content("Envelope")
      end
      expect(find("[data-figure='claim']").text).to eq("$150.00")
      within("[data-building-progress]") { expect(page).to have_content("0% complete") }
      expect(retirement.building_rule).to eq(retirement.budgets.sole)
    end

    # ** THE OTHER DIRECTION, AND IT IS THE ONE THE OLD PREDICATE GOT WRONG. ** A figure on the
    # CATEGORY with a rule whose money RESETS is an envelope somebody set a ceiling on: nothing about
    # it builds up, and no claim formula has read that column since the shapes moved onto the rule.
    # It got the "Goal" heading and a progress bar; it gets neither now.
    it "calls a category with a figure of its own and a resetting rule an envelope" do
      groceries = holder("Groceries")
      create(:budget, :per_period_rate, category: groceries, amount: 400)
      groceries.update!(target_amount: 5_000)

      visit category_path(groceries)

      within(card) do
        expect(page).to have_content("Envelope")
        expect(page).to have_no_content("Fund")
      end
      expect(page).to have_no_css("[data-building-progress]")
    end
  end

  # A HOLDER WITH NO RULE AT ALL. Every claim comes from a rule (§3.3), so this category claims
  # exactly nothing however much has been spent on it — and the $0.00 needs saying, or it reads as an
  # envelope somebody emptied. The old sentence named the two ways money used to arrive ("when you
  # distribute or move some in by hand"); there is one way now, and it is a rule.
  describe "a category with no rule claiming it", :aggregate_failures do
    it "claims nothing, and says a rule is what would change that" do
      cushion = holder("Cushion")
      spend(cushion, 120)

      visit category_path(cushion)

      expect(card["data-holdings-state"]).to eq("holding")
      expect(find("[data-figure='claim']").text).to eq("$0.00")
      expect(card).to have_no_css("[data-holdings-rules]")
      expect(find("[data-figure='no-rules']").text).to include("No rule claims this category's money")
      within(card) { expect(page).to have_no_content("distribute") }
    end
  end

  # ------------------------------------------------------------------------------------------
  # State 2 — nothing claims this category
  # ------------------------------------------------------------------------------------------

  describe "a category nothing claims", :aggregate_failures do
    let!(:streaming) { create(:category, :expense, user: user, name: "Streaming") }

    it "says its spending comes straight out of what's free to spend" do
      visit category_path(streaming)

      expect(card["data-holdings-state"]).to eq("unfunded")
      within(card) do
        expect(page).to have_content("Unbudgeted")
        expect(page).to have_content("Nothing claims this category's money.")
        expect(page).to have_content("comes straight out of what's free to spend")
        expect(page).to have_no_content("available")
      end
    end

    # THE OTHER DIRECTION: no figure, no bar and no rule list, because this arm has no claim to be
    # about. The sentence above is about SPENDING and it is exact —
    # `CategoryLedger::ENTRY_CATEGORY_ID` yields NULL for a NULL `funded_since`, so no rule's lane
    # can hold one of this category's receipts. (A rule written on such a category does go on
    # accruing, which is what the Budget page's own band is for; this card's subject is the
    # category.)
    it "claims no figure and no bar for it" do
      visit category_path(streaming)

      expect(card).to have_no_css("[data-figure='claim']")
      expect(card).to have_no_css("[data-building-progress]")
      expect(card).to have_no_css("[data-holdings-rules]")
      within(card) { expect(page).to have_no_content("Claiming since") }
    end

    # THE SHARPEST HALF. `SuggestionEngine#unfunded_categories` is `reject(&:holder?)` — literally
    # this arm's own population — so this is precisely the shape the panel is most likely to be
    # proposing a rule for, and a rule is now this category's ONLY way out (§5 closed the allocation
    # that used to be the second door).
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

    # And with nothing proposed the card is still not a dead end: it makes the offer in the words the
    # entry form's honest card already uses for this exact shape.
    it "offers the rule directly when nothing is proposed" do
      visit category_path(streaming)

      expect(card).to have_no_css("[data-suggestion-pointer]")
      within(card) { expect(page).to have_link("Give it a rule on the Budget page", href: budget_page_path) }
    end

    # The holding arm never runs the engine at all — see CategoryBudgetPresenter#suggestions' cost
    # note.
    it "never renders on a category whose rules claim its money" do
      groceries = holder("Groceries")
      rate(groceries, 400)

      visit category_path(groceries)

      expect(card["data-holdings-state"]).to eq("holding")
      expect(card).to have_no_css("[data-suggestion-pointer]")
    end
  end

  # AN INCOME CATEGORY CANNOT CLAIM BY THE MODEL'S OWN RULE (`Category#holder?` is `expense? && …`),
  # so there is no card at all rather than an arm that would be true and useless.
  describe "an income category", :aggregate_failures do
    it "gets no holdings card" do
      salary = create(:category, :income, user: user, name: "Salary")

      visit category_path(salary)

      expect(page).to have_content("Salary")
      expect(page).to have_no_css("[data-holdings-card]")
    end
  end

  private

  # A BILL'S SHAPE, straight into `SuggestionEngine`'s dated-bill detector: two payments of the
  # same size a whole month apart, on an item carrying no rule of its own.
  def bill(target, amount:)
    item = create(:item, category: target)
    [2, 1].each { |months| create(:entry, item: item, amount: amount, date: Date.current - months.months) }
  end
end
