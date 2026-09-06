# frozen_string_literal: true

require "rails_helper"

# THE SACRIFICE VIEW (spec §9): the screen that answers "what do I sacrifice" when reallocation
# cannot help, and the dial that answers it live.
#
# `Capybara.exact` is unset in this suite, so every figure is scoped to its own `data-figure` or
# its own row: unscoped, "$2,400.00" matches the income line from inside the totals block and a
# swapped pair would pass.
#
# EVERY FIXTURE HERE IS BIWEEKLY, so a monthly rule's amount and its per-period claim are never the
# same number. A suite of per-period rules would pass with the mixed-unit slip in place, and that
# slip has struck five times on this branch.
RSpec.describe "Sacrifice view", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end

  before { sign_in user, scope: :user }

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built here in the pool
  # era, one record shorter. Every figure on this page is `Budget#steady_ask`, which reads the RULE
  # and never its owner, so the conversion moves no number on the screen; what it changes is the
  # name each row prints, which `BudgetPageHelper#budget_rule_name` now reads off the category.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  # Anchorless per-period: a rate, and cuttable.
  def rate(name, amount, priority: 1)
    create(:budget, :per_period_rate, category: holder(name, priority: priority), amount: amount)
  end

  # Anchorless MONTHLY: also a rate and also cuttable, but its per-period claim is
  # `amount * 12 / 26` — nothing like its own amount. This is the shape the dial's units live or
  # die on.
  def monthly_rate(name, amount, priority: 1)
    create(:budget, :rate, category: holder(name, priority: priority), amount: amount)
  end

  # Anchored and recurring: a bill, and fixed.
  def rolling(name, amount, priority: 1, anchor: Date.current + 2.months, every: 1)
    create(
      :budget,
      category: holder(name, priority: priority),
      amount: amount,
      interval_months: every,
      anchor_date: anchor
    )
  end

  # Anchored with no interval: a one-off, marked `dated` rather than `fixed`.
  def one_off(name, amount, priority: 1, anchor: Date.current + 10.days)
    create(:budget, :one_time, category: holder(name, priority: priority), amount: amount, anchor_date: anchor)
  end

  def figure(name) = find("[data-figure='#{name}']")

  def row(rule) = find("[data-sacrifice-row='#{rule.id}']")

  def fixed_row(rule) = find("[data-fixed-row='#{rule.id}']")

  # ONE CUT, DIALLED THE WAY A USER DIALS IT: tick the row, then type what you would keep it at.
  # Scoped to the row because `Capybara.exact` is unset — "Cut Groceries" is a substring of nothing
  # else here today, and one rename away from being a substring of something.
  def cut(rule, label, to:)
    within(row(rule)) do
      check "Cut #{label}"
      fill_in "Cut #{label} to", with: to
    end
  end

  # $2,000 of groceries, $150 of dining and a $1,500-a-month rent that claims $692.31 of a
  # biweekly period: $2,842.31 of rules against $2,400 of income, so the gap is $442.31 and the
  # $2,150 of rate rules can close it several times over.
  def winnable_budget
    {
      groceries: rate("Groceries", 2_000),
      dining: rate("Dining Out", 150, priority: 2),
      rent: rolling("Rent", 1_500, priority: 3)
    }
  end

  describe "a budget the cuts could close" do
    let(:rules) { winnable_budget }

    before do
      rules
      visit sacrifice_path
    end

    # §9'S HEADLINE: the gap, then the two figures it came from — the same two the Budget page's
    # structural check prints, so a user arriving from that button meets the number they just read.
    it "opens on the gap and the figures behind it", :aggregate_failures do
      expect(figure("gap")).to have_content("$442.31 underwater every period")
      expect(figure("rules-need")).to have_content("$2,842.31")
      expect(figure("typical-income")).to have_content("$2,400.00")
    end

    # NO FALSE COMFORT CUTS BOTH WAYS. The unwinnable statement is a hard claim about the budget,
    # and printing it on a budget the user CAN fix would be its own kind of lie.
    it "says nothing about being unwinnable" do
      expect(page).to have_no_css("[data-unwinnable]")
    end

    # ** THE LIST'S ORDER IS STATED, AND IT IS TRUE (fix wave — LOW-3). ** `SacrificePresenter#rows`
    # sorts `[-claim, owner name, id]` and the page said nothing about it, which leaves a column of
    # money in an order a reader has to guess at. Both halves are asserted together: the sentence,
    # and the order it describes — Groceries ($2,000) then Rent ($692.31 of a period) then Dining
    # Out ($150), which is neither alphabetical nor the order they were written in.
    it "says the biggest claim is first, and lists them that way", :aggregate_failures do
      expect(find("[data-cut-list-order]")).to have_content("The biggest claim is first")
      expect(page.all("[data-sacrifice-row]").pluck("data-sacrifice-row"))
        .to eq([rules.fetch(:groceries).id, rules.fetch(:dining).id])
      expect(page.all("[data-fixed-row]").pluck("data-fixed-row")).to eq([rules.fetch(:rent).id])
    end

    it "opens with nothing cut and the whole gap still open", :aggregate_failures do
      expect(figure("frees")).to have_content("$0.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $442.31 a period")
    end

    # THE DIAL, THROUGH THE BROWSER — two cuts, and the totals read at each step. The arithmetic is
    # the whole point: $2,000 cut to $1,800 frees $200, $150 cut to nothing frees $150, and the
    # $442.31 gap closes to $92.31.
    it "recomputes the totals as cuts are dialled in", :aggregate_failures do
      cut(rules[:groceries], "Groceries", to: "1800")

      expect(figure("frees")).to have_content("$200.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $242.31 a period")

      cut(rules[:dining], "Dining Out", to: "0")

      expect(figure("frees")).to have_content("$350.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $92.31 a period")
    end

    # EACH ROW SAYS WHAT ITS OWN CUT FREES (§9's `frees $100`), because the footer's total cannot
    # say which of nine ticked rows produced it. Both directions on one screen: the row that was
    # cut and the row beside it that was not.
    it "says what each row's own cut frees", :aggregate_failures do
      cut(rules[:groceries], "Groceries", to: "1800")

      expect(row(rules[:groceries]).find("[data-role='row-frees']")).to have_content("frees $200.00")
      expect(row(rules[:dining]).find("[data-role='row-frees']")).to have_content("frees $0.00")
    end

    # THE OTHER SIDE OF THE VERDICT. A dial that could only ever say "still underwater" would be
    # telling a user their cuts do not work when they do.
    it "flips to covered once the cuts outrun the gap", :aggregate_failures do
      cut(rules[:groceries], "Groceries", to: "1500")

      expect(figure("frees")).to have_content("$500.00 a period")
      expect(figure("verdict")).to have_content("Covered — $57.69 a period to spare")
      expect(figure("verdict")).to have_no_content("Still underwater")
    end

    # A TICKED BOX WITH NO CHANGE IS NOT A CUT, and an unticked one with a figure in it is not
    # either. Both directions, because a controller that ignored the checkbox would pass the first
    # and a controller that ignored the field would pass the second.
    it "frees nothing from a row that is ticked but unchanged", :aggregate_failures do
      within(row(rules[:groceries])) { check "Cut Groceries" }

      expect(figure("frees")).to have_content("$0.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $442.31 a period")
    end

    it "frees nothing from a row that is typed into but not ticked", :aggregate_failures do
      within(row(rules[:groceries])) { fill_in "Cut Groceries to", with: "0" }

      expect(figure("frees")).to have_content("$0.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $442.31 a period")
    end

    # Typing MORE than the rule already claims is not a cut. Without the floor this reads as a
    # NEGATIVE contribution and the total would go the wrong way on a screen about closing a gap.
    it "frees nothing from a row dialled above its own claim" do
      cut(rules[:groceries], "Groceries", to: "5000")

      expect(figure("frees")).to have_content("$0.00 a period")
    end

    # THE OTHER END OF THE SAME CLAMP: an EMPTY "cut to" box frees the rule entirely. That is the
    # honest reading of a cleared field — the user has named no floor — and it is the conservative
    # one for the totals, since the clamp caps it at the rule's own claim rather than letting a
    # `NaN` through. It is also where a pasted "1,800" lands: a `type=number` input rejects the
    # comma in some browsers and hands the dial a blank, so this state is reachable without anyone
    # meaning to reach it. Pinned at the ROW as well as the footer, so the screen says which rule
    # produced the figure.
    #
    # `fill_in with: ""` is a PROGRAMMATIC clear — it dispatches `change` and no `input` — and that
    # is the half of the mechanism worth exercising here, because it is the same half a paste or an
    # autofill uses. Writing this example is what found that the input listened for `input` alone
    # and left the total stale beside an empty box; the keystroke path was measured separately and
    # was always correct (typing "100" and backspacing it away moves the total on every press).
    it "frees the whole claim from a row whose cut-to box is empty", :aggregate_failures do
      cut(rules[:groceries], "Groceries", to: "")

      expect(row(rules[:groceries]).find("[data-role='row-frees']")).to have_content("frees $2,000.00")
      expect(figure("frees")).to have_content("$2,000.00 a period")
      expect(figure("verdict")).to have_content("Covered — $1,557.69 a period to spare")
    end

    # BREAK-EVEN, TO THE CENT: cutting exactly the gap. `remaining` is 0 here, which in JavaScript
    # is `-0` after the subtraction, and `Intl.NumberFormat().format(-0)` is "-$0.00" — so this one
    # keystroke printed `Covered — -$0.00 a period to spare`, a minus sign on the only figure that
    # has no sign. `have_no_content("-$")` is the assertion that catches it coming back.
    it "reads level, not negative, when the cuts land exactly on the gap", :aggregate_failures do
      cut(rules[:groceries], "Groceries", to: "1557.69")

      expect(figure("frees")).to have_content("$442.31 a period")
      expect(figure("verdict")).to have_content("Covered — $0.00 a period to spare")
      expect(figure("verdict")).to have_no_content("-$")
    end

    # UNCUTTABLE RULES ARE LISTED AND MARKED (spec §9: "pretending rent is optional would be a
    # lie"), and they carry no checkbox at all — a control that did nothing would be worse than no
    # control.
    it "lists the anchored rule as fixed, with no way to cut it", :aggregate_failures do
      expect(fixed_row(rules[:rent])).to have_content("fixed")
      expect(fixed_row(rules[:rent])).to have_content("$692.31 a period")
      expect(fixed_row(rules[:rent])).to have_no_css("input[type='checkbox']")
    end

    # THE ROW IS WHERE THE CUT IS ACTUALLY MADE. This page writes nothing (plan decision 3), so
    # the only way off it is the rule's own edit form.
    it "links each row to the rule's edit form", :aggregate_failures do
      within(row(rules[:groceries])) { click_link "Edit the rule" }

      expect(page).to have_current_path(edit_budget_path(rules[:groceries]))
      expect(page).to have_field("Amount")
    end
  end

  # THE MIXED-UNIT TRAP, THROUGH THE BROWSER. A $1,500-a-month rule claims $692.31 of a biweekly
  # period. Both figures are on the row — the claim this page adds up and the amount the edit form
  # will show — and the dial must free the FIRST. Freeing $1,500 out of a $2,400 period by
  # ticking one box is the defect this example exists for, and it would look entirely plausible.
  describe "a monthly rule in a biweekly period" do
    let(:streaming) { monthly_rate("Streaming", 1_500) }

    # $2,500 of groceries beside it, because the route refuses a budget that fits: $692.31 + $1,500
    # is under the declared $2,400 and this page would never render. The gap is $792.31.
    before do
      streaming
      rate("Groceries", 2_500, priority: 2)
      visit sacrifice_path
    end

    it "prints the per-period claim beside the rule's own amount", :aggregate_failures do
      expect(row(streaming)).to have_content("$692.31 a period")
      expect(row(streaming)).to have_content("$1,500.00 a month")
    end

    it "frees the per-period claim and not the rule's amount", :aggregate_failures do
      cut(streaming, "Streaming", to: "0")

      expect(figure("frees")).to have_content("$692.31 a period")
      expect(figure("frees")).to have_no_content("$1,500.00")
    end
  end

  # THE UNWINNABLE CASE (spec §9: "if every available cut still leaves a gap, the app says so
  # instead of offering false comfort"). $200 of rate against a $7,500-a-month rent: the rent alone
  # claims $3,461.54 of a biweekly period, so the gap is $1,261.54 and cutting every cuttable
  # dollar leaves $1,061.54 of it.
  describe "a budget no cut can close" do
    let(:groceries) { rate("Groceries", 200) }

    before do
      groceries
      rolling("Rent", 7_500, priority: 2)
      visit sacrifice_path
    end

    it "opens by saying so, with the number", :aggregate_failures do
      expect(page).to have_css("[data-unwinnable]")
      expect(find("[data-unwinnable]")).to have_content("$1,061.54 underwater every period")
      expect(find("[data-unwinnable]")).to have_content("This budget does not fit this income")
    end

    # The dial still works underneath the statement: a user who cannot win still wants to see how
    # close they can get, and the verdict has to be able to say the same thing the statement does.
    it "still dials, and still cannot be made to cover", :aggregate_failures do
      cut(groceries, "Groceries", to: "0")

      expect(figure("frees")).to have_content("$200.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $1,061.54 a period")
      expect(figure("verdict")).to have_no_content("Covered")
    end
  end

  # THE WORST VERSION: every rule anchored, so there is nothing on the screen to dial at all. The
  # list would otherwise render as a heading over nothing, which on a money screen reads as data
  # that failed to load.
  describe "a budget with nothing anchorless in it" do
    before do
      rolling("Rent", 7_500)
      visit sacrifice_path
    end

    it "says why the list has no checkboxes in it", :aggregate_failures do
      expect(page).to have_content("Every rule you have is anchored to a date")
      expect(page).to have_css("[data-unwinnable]")
      expect(page).to have_no_css("[data-sacrifice-row]")
    end

    # THE TWO BLOCKS HAVE TO AGREE. The statement said "cutting every rule BELOW to nothing" over an
    # empty state saying "There is nothing here to cut" — a screen contradicting itself two inches
    # apart. `have_no_content("rule below")` is what keeps the old scope from returning.
    it "does not promise rows the list has none of", :aggregate_failures do
      expect(find("[data-unwinnable]")).to have_content("Cutting every rule you can cut to nothing")
      expect(find("[data-unwinnable]")).to have_no_content("rule below")
      expect(page).to have_content("There is nothing here to cut")
    end
  end

  describe "the rules that never appear here" do
    # The category-cap example is deleted with the shape (plan 3, task 3): it planted a $600 cap and
    # checked that it appeared in neither list and in neither figure, and a rule owned by a category
    # is not something this app can hold. Nothing is left out of this page's arithmetic now.

    # ** A ONE-OFF IS OFFERED, AND ONLY THE RECURRING BILL IS FIXED (fix round 1 — MED-4). ** The
    # page marked both — "can't cut — dated" against "fixed — the bill is what it is" — and the first
    # of those took every SAVINGS GOAL off the cut list the moment a goal became a one-off
    # (two-shapes §2), on the one screen whose subject is closing a structural gap. A dentist
    # appointment on a day the user chose IS a decision; a landlord's rent is not.
    #
    # BOTH ON ONE SCREEN, so a page that had simply stopped marking anything would fail the second
    # half.
    it "offers a dated one-off and fixes only the recurring bill", :aggregate_failures do
      rate("Groceries", 3_000)
      dentist = one_off("Dentist", 300, priority: 2)
      rent = rolling("Rent", 1_500, priority: 3)

      visit sacrifice_path

      expect(page).to have_no_css("[data-fixed-row='#{dentist.id}']")
      expect(row(dentist)).to have_content("Dentist")
      expect(fixed_row(rent)).to have_content("fixed — the bill is what it is")
      expect(page).to have_no_content("can't cut — dated")
    end
  end

  # THE ROUTE REFUSES IN THE TWO STATES NEITHER BUTTON CAN BE SHOWN IN, and they are two different
  # refusals: one user has not asked a question this page could answer, the other asked it and got
  # "yes". Sending both to one sentence would tell the second to declare something they declared.
  describe "arriving when there is nothing to cut" do
    it "sends a covered user back to the Budget page and says why", :aggregate_failures do
      rate("Groceries", 400)

      visit sacrifice_path

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Your rules already fit what you bring in")
    end

    it "sends an undeclared user back to declare, however large their rules", :aggregate_failures do
      user.update!(typical_income: nil, period_cadence: nil, period_anchor_date: nil)
      rate("Groceries", 9_000)

      visit sacrifice_path

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Tell us how long a period is and what you typically bring in")
      expect(page).to have_no_content("underwater every period")
    end

    # INCOME WITHOUT A CADENCE IS REACHABLE — the declaration form offers "Not set" for the period
    # and keeps the income — and in it every figure this page prints would be denominated in a
    # period the user has not agreed to.
    it "refuses when the income is declared but the period is not", :aggregate_failures do
      user.update!(period_cadence: nil, period_anchor_date: nil)
      rate("Groceries", 9_000)

      visit sacrifice_path

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Tell us how long a period is")
    end
  end
end
