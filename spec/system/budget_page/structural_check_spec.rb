# frozen_string_literal: true

require "rails_helper"

# THE STRUCTURAL CHECK (spec §8's three lines, §9's gate) and the declaration form under it — the
# first and only writer in the app for `typical_income`, `period_cadence` and `period_anchor_date`.
#
# `Capybara.exact` is unset in this suite, so every figure assertion is scoped to its own
# `data-figure` row: unscoped, "$2,400.00 a period" matches the income line from inside the rules
# line's own container and a swapped pair of labels would pass.
RSpec.describe "Budget page structural check", type: :system do
  let(:user) { create(:user) }

  before { sign_in user, scope: :user }

  def check_block = find("[data-structural-check]")

  def figure(name) = find("[data-figure='#{name}']")

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built here in the pool
  # era. Every figure this block prints is `Budget.steady_need`, which reads the RULE and never its
  # owner, so the conversion moves no number on the page.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  def declare(income:, cadence:, anchor:)
    fill_in "You typically bring in", with: income
    select cadence, from: "How long is a period?"
    fill_in "A day a period starts", with: anchor
    click_button "Save period and income"
  end

  # A user who has declared a period, so the figures below have a unit.
  def declared_user(income)
    user.update!(typical_income: income, period_cadence: :biweekly, period_anchor_date: Date.current)
  end

  # STATE ONE OF THREE: nothing declared. The block invites rather than reports, and there is no
  # button — a comparison nobody has made cannot have an answer.
  describe "before anything is declared", :aggregate_failures do
    before do
      rate(holder("Rent"), 3_000)
      visit budget_page_path
    end

    it "invites a declaration instead of printing figures" do
      within(check_block) do
        expect(page).to have_content("Tell us how long a period is and what you typically bring in")
        expect(page).to have_no_css("[data-figure]")
      end
    end

    it "shows no sacrifice button" do
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    it "offers all three fields" do
      expect(page).to have_field("You typically bring in")
      expect(page).to have_select("How long is a period?")
      expect(page).to have_field("A day a period starts")
    end
  end

  # THE FORM IS OUTSIDE THE EMPTY STATE, deliberately. A user who has declared nothing is usually
  # a user who has made nothing, and putting the block inside the `no_rules?` else-branch would
  # leave the only writer in the app for these three columns unreachable until they had built a
  # rule first.
  describe "a brand-new user with no rules at all", :aggregate_failures do
    before { visit budget_page_path }

    it "still gets the declaration form under the empty state" do
      expect(page).to have_content("No funding rules yet")
      expect(page).to have_field("You typically bring in")
      expect(page).to have_button("Save period and income")
    end
  end

  # STATE TWO OF THREE: declared and covered. Figures, no button.
  describe "when the rules fit the income", :aggregate_failures do
    before do
      declared_user(2_400)
      rate(holder("Groceries"), 400)
      create(:budget, :rate, category: holder("Utilities", priority: 2), amount: 260)
      visit budget_page_path
    end

    # $400 a period passes straight through; $260 a month under a biweekly period is $120, NOT
    # $260 — the mixed-unit figure the rate normalisation exists to get right, asserted on the
    # rendered page rather than only in the model.
    it "prints the three lines from the spec" do
      within(figure("rules-need")) { expect(page).to have_content("$520.00 a period") }
      within(figure("typical-income")) { expect(page).to have_content("$2,400.00 a period") }
      within(figure("leftover")) { expect(page).to have_content("$1,880.00 → buffer") }
    end

    it "shows no sacrifice button and does not call the budget underwater" do
      expect(page).to have_no_css("[data-sacrifice-link]")
      within(check_block) { expect(page).to have_no_content("Underwater") }
    end

    # THE CAPS NOTE IS GONE FROM THE PAGE (plan 3, task 3), so this asserts its absence rather than
    # the conditions it used to appear under. Two examples stood here: one planted a $650 cap and
    # checked that neither the figure nor the block mentioned it, and one gave a user caps and
    # nothing else so the block explained its own $0.00. A rule owned by a category is not a shape
    # the app can hold, so both fixtures are unbuildable and both examples are deleted with the
    # behaviour. What survives is the guarantee the note's deletion has to keep: nothing on this
    # page still talks about caps.
    it "says nothing about category caps anywhere" do
      expect(page).to have_no_css("[data-caps-note]")
      within(check_block) { expect(page).to have_no_content("spending limits") }
    end
  end

  # ZERO NEED IS NOW THE BRAND-NEW USER AND NOTHING ELSE. It used to be the legacy shape too —
  # caps and no funding rules — which is what the deleted note explained.
  describe "a declared user with no rules at all", :aggregate_failures do
    before do
      declared_user(2_400)
      visit budget_page_path
    end

    it "reads zero with no explanation to give" do
      within(figure("rules-need")) { expect(page).to have_content("$0.00 a period") }
      within(figure("leftover")) { expect(page).to have_content("$2,400.00 → buffer") }
      expect(page).to have_no_css("[data-caps-note]")
    end

    it "is covered rather than underwater, and offers no cut list" do
      expect(page).to have_no_css("[data-sacrifice-link]")
      within(check_block) { expect(page).to have_no_content("Underwater") }
    end
  end

  # STATE THREE OF THREE: declared and underwater. Figures AND the button.
  #
  # GENUINELY UNDERWATER ON STEADY NEED, not on catch-up: a flat $3,000-a-period rule against
  # $2,400 of income is broken on every period there will ever be.
  describe "when the rules outrun the income", :aggregate_failures do
    before do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)
      visit budget_page_path
    end

    it "states the gap the way the sacrifice view states it" do
      within(figure("rules-need")) { expect(page).to have_content("$3,000.00 a period") }
      within(figure("leftover")) { expect(page).to have_content("Underwater").and have_content("$600.00 a period") }
      within(figure("leftover")) { expect(page).to have_no_content("buffer") }
    end

    # The button points at Task 9's sacrifice view, which is not routed yet. The link's presence
    # and its target are what this task owns; that the target answers is Task 9's.
    it "offers the way out" do
      expect(page).to have_css("[data-sacrifice-link]")
      # `end_with`, because the driver hands back an absolute URL with the test server's port in
      # it — the path is the part this task owns.
      expect(find("[data-sacrifice-link]")[:href]).to end_with("/sacrifice")
      expect(page).to have_link("What could you cut?")
    end
  end

  # THE CASE AMENDMENT A EXISTS FOR. A $5,200 annual premium falling due in three days asks for
  # all $5,200 out of THIS period — but its standing claim is $200 a period against $2,400 of
  # income, and nothing about that budget is structurally broken. The old reader compared this
  # period's ask and would have shown the button here.
  describe "a catch-up period on a budget that fits", :aggregate_failures do
    before do
      declared_user(2_400)
      create(
        :budget,
        category: holder("Car Insurance"),
        amount: 5_200,
        interval_months: 12,
        anchor_date: Date.current + 3.days
      )
      visit budget_page_path
    end

    it "reads the standing claim, not this period's ask" do
      within(figure("rules-need")) do
        expect(page).to have_content("$200.00 a period")
        expect(page).to have_no_content("$5,200.00")
      end
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    # Both screens, one afternoon, one budget. Home's standing band reads the same redefined
    # figure, so a user cannot be told their budget fits on one page and does not on the other.
    it "does not warn on Home either" do
      visit root_path

      expect(page).to have_no_content("Your budget doesn't fit your income")
    end
  end

  # HOME'S STANDING BAND, both directions. The branch has been unreachable in production since it
  # was written — there was no writer for `typical_income` — so this is the first time it renders
  # against a real user.
  describe "Home's standing band", :aggregate_failures do
    it "warns when the budget does not fit" do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)

      visit root_path

      expect(page).to have_content("Your budget doesn't fit your income")
    end

    # THE TWO GATES ARE ONE GATE. `/budget` withholds its figures until income AND cadence exist,
    # because "$3,000.00 a period" at someone who has not said how long a period is states a
    # figure with no unit. Home used to gate on income alone, so the same user got the VERDICT
    # those figures justify without the figures — and the verdict was computed from
    # `steady_need`'s monthly fallback, a per-rule convenience that is not a reading of anyone's
    # budget.
    #
    # Both directions on one fixture, and the screens paired: with the cadence declared, Home
    # warns and `/budget` prints the figures; with it cleared, both fall silent together.
    it "says nothing when income is declared but no period is" do
      declared_user(2_400)
      rate(holder("Rent"), 3_000)

      visit root_path
      expect(page).to have_content("Your budget doesn't fit your income")

      user.update!(period_cadence: nil, period_anchor_date: nil)

      visit root_path
      expect(page).to have_no_content("Your budget doesn't fit your income")

      visit budget_page_path
      expect(page).to have_no_css("[data-figure]")
      expect(page).to have_no_css("[data-sacrifice-link]")
    end

    it "stays silent when it does" do
      declared_user(2_400)
      rate(holder("Groceries"), 400)

      visit root_path

      expect(page).to have_no_content("Your budget doesn't fit your income")
    end
  end

  # THE DECLARATION ITSELF, end to end: the figures on this page are computed from data that until
  # now only seeds could write.
  describe "declaring a period and an income", :aggregate_failures do
    before do
      rate(holder("Groceries"), 400)
      create(:budget, :rate, category: holder("Utilities", priority: 2), amount: 260)
      visit budget_page_path
    end

    it "persists it and re-derives the block from it" do
      declare(income: "2400", cadence: "Biweekly", anchor: Date.current.strftime("%Y-%m-%d"))

      expect(page).to have_current_path(budget_page_path)
      within(figure("rules-need")) { expect(page).to have_content("$520.00 a period") }
      within(figure("typical-income")) { expect(page).to have_content("$2,400.00 a period") }
      expect(user.reload.period_cadence).to eq("biweekly")
    end

    # DECISION 6, and the reason the copy under the form says what it says: the same two rules,
    # the same income, a different period — and every figure moves. Under a monthly period the
    # $260-a-month rule claims its whole $260 and the $400-per-period rule is $400 of a month.
    it "re-derives every figure the moment the cadence changes" do
      declare(income: "2400", cadence: "Biweekly", anchor: Date.current.strftime("%Y-%m-%d"))
      within(figure("rules-need")) { expect(page).to have_content("$520.00 a period") }

      select "Monthly", from: "How long is a period?"
      click_button "Save period and income"

      within(figure("rules-need")) { expect(page).to have_content("$660.00 a period") }
    end

    it "says so on the form" do
      expect(page).to have_content("Changing your period re-derives every figure immediately")
    end

    # A cadence with no anchor yields no boundaries at all, and the divisors downstream then clamp
    # to 1 — the app would demand whole bills out of the next period. `User` refuses it; the page
    # has to show the refusal rather than 500 or silently drop half the submission.
    it "refuses a period with no anchor, and writes nothing" do
      fill_in "You typically bring in", with: "2400"
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      expect(page).to have_css("[data-declaration-error]")
      within("[data-declaration-error]") { expect(page).to have_content("required when you set a period") }
      expect(user.reload.typical_income).to be_nil
      expect(user.reload.period_cadence).to be_nil
    end

    # A DEFECT THE BROWSER CAUGHT. A failed `update` leaves the rejected values on the in-memory
    # user, and the block was rendered from that object — so a refused submission printed "Your
    # rules need $520.00 a period / You typically bring in $2,400.00 / Left over $1,880.00 →
    # buffer" directly under the error saying nothing had been saved, and a page reload made all
    # three lines disappear. The figures now read the row; the form keeps what was typed.
    it "prints no figures it did not save, while keeping what was typed" do
      fill_in "You typically bring in", with: "2400"
      select "Biweekly", from: "How long is a period?"
      click_button "Save period and income"

      within(check_block) do
        expect(page).to have_content("Tell us how long a period is")
        expect(page).to have_no_css("[data-figure]")
        expect(page).to have_no_content("$2,400.00 a period")
      end
      expect(page).to have_field("You typically bring in", with: "2400")
      expect(page).to have_select("How long is a period?", selected: "Biweekly")
    end
  end
end
