# frozen_string_literal: true

require "rails_helper"

# The impact card on the entry form, read out of a real browser after real typing against the same
# planted literals `EntryImpactPresenter`'s own spec uses: a subtraction that diverges between Ruby
# and JavaScript fails on one side rather than agreeing quietly on a wrong number.
#
# Every figure is scoped to its own `data-figure` inside the card — unscoped, "$240.00" would match
# the balance from an assertion about the balance-after and a swapped pair would pass.
#
#   $240 in Groceries     → a $300-a-period rate with $60 of it spent
#   $1,500 in Rent        → a $1,500-a-period rate with nothing spent
#   $600 in Vacation      → a $2,400 target four fortnights out, one period walked
#   $600 in House Deposit → a $600 bill due inside this period, so the catch-up asks for all of it
#   nothing in Shopping   → a category with no rule claims nothing
#
# Every fixture is biweekly: a monthly rule's amount and its per-period claim are never the same
# number, and a dated rule starts today so that exactly one period is walked.
RSpec.describe "Entry impact card", :js, type: :system do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }

  # $240 claimed against a $300-a-period rate: the rate less what has been spent this period. The
  # $60 sits on an item of its own so the "Weekly shop" item the editing examples use stays empty.
  let!(:groceries) do
    create(:category, :expense, user: user, name: "Groceries").tap do |category|
      create(:rule, :rate, category: category, amount: 300)
      create(:item, category: category, name: "Weekly shop")
      create(:entry, item: create(:item, category: category, name: "Earlier shop"), amount: 60, date: Date.current)
    end
  end

  # By name: the category carries two items and `items.first` is unordered.
  def weekly_shop = groceries.items.find_by(name: "Weekly shop")

  # The two categories every other state needs, reached by name through the select: an expense no
  # rule claims, and an income one.
  before do
    create(:category, :expense, user: user, name: "Shopping")
    create(:category, user: user, name: "Paycheck", category_type: :income)
    sign_in user, scope: :user
  end

  # The control rather than the input inside it: TomSelect sets that input to `opacity: 0` on a
  # select that already has a value, so on an edit page the click cannot land on it. The wait at the
  # end is for the item list the change refetches — the stamp says whose list is on screen.
  def select_category(name)
    expect(page).to have_css("#category_id-ts-control", visible: :all, wait: 10)
    find("#category_id-ts-control", visible: :all).find(:xpath, "..").click
    find("#category_id-ts-dropdown .option", text: name).click
    expect(page).to have_css("[data-items-loaded='#{user.categories.find_by!(name: name).id}']")
  end

  def card = find("[data-impact-card]")

  def figure(name) = find("[data-figure='#{name}']")

  # A biweekly period anchored on today closes on the thirteenth day after it.
  def period_end_label = (Date.current + 13).strftime("%b %-d")

  describe "a ruled category the spending fits inside" do
    before do
      visit new_entry_path
      select_category("Groceries")
    end

    it "opens on the rules, their balance and the day the period runs to", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='rules']")

      within(card) do
        expect(figure("title")).to have_text("Groceries rules")
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("$240.00")
        expect(figure("period-end")).to have_text("until #{period_end_label}")
      end
    end

    # 240 of a 300-a-period claim.
    it "draws the bar at what is left over what the rules claim from a period" do
      expect(page).to have_css("[data-figure='bar'][style*='width: 80%']")
    end

    it "says nothing about a status, in either vocabulary", :aggregate_failures do
      within(card) do
        expect(page).not_to have_text("on track")
        expect(page).not_to have_text("behind")
        expect(page).not_to have_text("left to spend")
      end
    end

    it "subtracts what is typed and redraws the bar", :aggregate_failures do
      fill_in "Amount", with: "55"

      within(card) do
        expect(figure("balance-after")).to have_text("$185.00")
        expect(figure("balance")).to have_text("$240.00")
      end
      # 185 of 300.
      expect(page).to have_css("[data-figure='bar'][style*='width: 62%']")
    end

    it "follows the numpad, which types without a keyboard", :aggregate_failures do
      click_button "Calculator"
      click_button "5"
      click_button "5"

      expect(page).to have_field("Amount", with: "55")
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
    end

    # A value written into the box by something other than a keystroke dispatches `change` and no
    # `input` at all, and the user never sees a keystroke that would wake a card listening only for
    # the latter.
    it "follows a value set without a keystroke, which dispatches only change" do
      page.execute_script(<<~JS)
        const box = document.getElementById("entry_amount");
        box.value = "55";
        box.dispatchEvent(new Event("change", { bubbles: true }));
      JS

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
    end

    it "gives the whole claim back when the amount is cleared", :aggregate_failures do
      fill_in "Amount", with: "55"
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }

      fill_in "Amount", with: ""

      within(card) { expect(figure("balance-after")).to have_text("$240.00") }
      expect(page).to have_css("[data-figure='bar'][style*='width: 80%']")
    end

    it "keeps the ordinary submit label and stays quiet about free money", :aggregate_failures do
      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
      expect(page).not_to have_text("comes straight out of what's free")
    end

    # `parseFloat("10*5")` is 10 and Dentaku says 50 on save. Neither belongs on the card, so it
    # holds at the balance until the formula resolves into a number.
    it "holds still for a formula and moves for the number it resolves to", :aggregate_failures do
      fill_in "Amount", with: "10*5"
      within(card) { expect(figure("balance-after")).to have_text("$240.00") }

      fill_in "Amount", with: "50"
      within(card) { expect(figure("balance-after")).to have_text("$190.00") }
    end
  end

  describe "overdrawing the rules" do
    before do
      visit new_entry_path
      select_category("Groceries")
    end

    it "shows the claim going negative, says free money covers it, and does not block", :aggregate_failures do
      fill_in "Amount", with: "300"

      within(card) do
        expect(figure("balance-after")).to have_text("-$60.00")
        expect(figure("overdraw")).to have_text("This goes over its rules — the difference comes straight out of what's free.")
      end
      expect(page).to have_button("Save anyway")
      expect(page).not_to have_button("Create Entry")
      # `visible: :all` because an empty bar is a zero-width box, which Capybara counts as
      # invisible — the assertion is about the width itself.
      expect(page).to have_css("[data-figure='bar'][style*='width: 0%']", visible: :all)
    end

    it "puts everything back when the amount comes back inside the claim", :aggregate_failures do
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
      expect(page).not_to have_text("comes straight out of what's free")
    end

    # Spending a claim to the exact penny is level, not negative, and
    # `Intl.NumberFormat().format(-0)` is "-$0.00".
    it "reads level, not negative, when the claim is spent to the penny", :aggregate_failures do
      fill_in "Amount", with: "240"

      within(card) do
        expect(figure("balance-after")).to have_text("$0.00")
        expect(figure("balance-after")).to have_no_text("-$0.00")
      end
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end

    it "still saves, because nothing blocks", :aggregate_failures do
      find("#entry_item_id-ts-control").click
      find("#entry_item_id-ts-dropdown .option", text: "Weekly shop").click
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      click_button "Save anyway"

      expect(page).to have_content("Entry was successfully created")
      # Two: the fixture's own $60 receipt, which is what makes the claim $240, plus this one.
      expect(Entry.count).to eq(2)
      expect(Entry.where(amount: 300).count).to eq(1)
    end
  end

  # A $1,500 balance reaches the browser as `data-balance`, and `parseFloat("1,500.00")` is 1.5 —
  # a claim offering a dollar fifty. The delimiter is the defect this example would catch.
  describe "a category with four figures in it" do
    before do
      rent = create(:category, :expense, user: user, name: "Rent")
      create(:rule, :rate, category: rent, amount: 1_500)

      visit new_entry_path
      select_category("Rent")
    end

    it "subtracts from fifteen hundred and not from one dollar fifty", :aggregate_failures do
      fill_in "Amount", with: "100"

      within(card) do
        expect(figure("balance")).to have_text("$1,500.00")
        expect(figure("balance-after")).to have_text("$1,400.00")
        expect(figure("balance-after")).to have_no_text("-$98.50")
      end
    end
  end

  describe "a category no rule claims" do
    before do
      visit new_entry_path
      select_category("Shopping")
    end

    it "is told the truth and pointed at the Budget page", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='unbudgeted']")

      within(card) do
        expect(figure("headline")).to have_text("Nothing claims this yet — this spending isn't budgeted.")
        expect(page).to have_text("It comes straight out of what's free.")
        expect(page).to have_link("Give it a rule on the Budget page", href: budget_page_path)
      end
    end

    it "shows no rule figures at all", :aggregate_failures do
      expect(page).not_to have_css("[data-impact-card='rules']")
      expect(page).not_to have_css("[data-figure='balance']")
      expect(page).not_to have_css("[data-figure='bar']")
    end

    it "cannot be overdrawn, whatever is typed", :aggregate_failures do
      fill_in "Amount", with: "99999"

      expect(page).to have_no_css("[data-figure='overdraw']", visible: :all)
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end

    # The other direction on the same screen: give a category one rule and it gets a claim with a
    # figure and a bar. The pair is what makes this a pin on the rule rather than on the copy.
    it "unlike a category with a rule, which gets the claim, the figure and the bar", :aggregate_failures do
      select_category("Groceries")

      expect(page).to have_css("[data-impact-card='rules']")
      within(card) { expect(figure("balance")).to have_text("$240.00") }
      expect(page).to have_css("[data-figure='bar']", visible: :all)
    end
  end

  describe "an income category" do
    before do
      visit new_entry_path
      select_category("Paycheck")
    end

    # Income is left out on purpose: it lands in an account, and no rule claims it.
    it "gets no card at all, of either kind", :aggregate_failures do
      expect(page).to have_select("category_id", selected: "Paycheck")
      expect(page).not_to have_css("[data-impact-card]")
      expect(page).not_to have_text("No rules")
    end
  end

  describe "changing the category" do
    before { visit new_entry_path }

    it "re-renders the card for whichever rules the new category reaches", :aggregate_failures do
      select_category("Groceries")
      within(card) { expect(figure("title")).to have_text("Groceries rules") }

      select_category("Shopping")
      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(page).not_to have_css("[data-impact-card='rules']")

      select_category("Groceries")
      expect(page).to have_css("[data-impact-card='rules']")
      within(card) { expect(figure("balance")).to have_text("$240.00") }
    end

    it "carries the typed amount across the change rather than forgetting it", :aggregate_failures do
      select_category("Groceries")
      fill_in "Amount", with: "55"
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }

      select_category("Shopping")
      expect(page).to have_css("[data-impact-card='unbudgeted']")

      select_category("Groceries")
      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_field("Amount", with: "55")
    end

    it "drops the overdraw label with the claim it belonged to", :aggregate_failures do
      select_category("Groceries")
      fill_in "Amount", with: "300"
      expect(page).to have_button("Save anyway")

      select_category("Shopping")

      expect(page).to have_css("[data-impact-card='unbudgeted']")
      expect(page).to have_button("Create Entry")
      expect(page).not_to have_button("Save anyway")
    end
  end

  # The noun is the rule's own type: what a person accrues toward is either a bill somebody else
  # sets the day for or a target they chose.
  describe "a target" do
    before do
      vacation = create(:category, :expense, user: user, name: "Vacation")
      # $600 of a $2,400 target: four boundaries stand between today and the date, so one walked
      # period accrues `2,400 ÷ 4`.
      create(:rule, category: vacation, amount: 2_400, anchor_date: Date.current + 55.days, starts_on: Date.current)

      visit new_entry_path
      select_category("Vacation")
    end

    it "takes the fund shape and subtracts what is spent", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='target']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("title")).to have_text("Vacation target")
        expect(figure("balance")).to have_text("$600.00")
        expect(figure("balance-after")).to have_text("$450.00")
        expect(figure("target")).to have_text("of $2,400.00")
      end
    end

    # The attribute the browser used to multiply by is gone: with one direction left it would be
    # the constant -1 on every render.
    it "sends the browser no direction to decide", :aggregate_failures do
      expect(page).to have_no_css("[data-direction]")
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }
    end

    it "measures the bar against the rule's target", :aggregate_failures do
      fill_in "Amount", with: "150"
      within(card) { expect(figure("balance-after")).to have_text("$450.00") }

      # 450 of 2,400.
      expect(page).to have_css("[data-figure='bar'][style*='width: 19%']")
      expect(page).not_to have_css("[data-figure='bar'][style*='width: 100%']")
    end

    # A fund can go negative, and it says so in the app's ordinary overdraw vocabulary rather than
    # being exempted from it.
    it "reads as the fund going negative when it is emptied", :aggregate_failures do
      fill_in "Amount", with: "5000"

      within(card) { expect(figure("balance-after")).to have_text("-$4,400.00") }
      expect(page).to have_button("Save anyway")
    end
  end

  # The figure is the whole category's claim, so a fund sharing its category with a bill has no
  # ceiling to print: `$1,200.00 of $2,400.00` would read half full over a fund a quarter full.
  # The target plans `2,400 ÷ 4` = $600 and the bill due three days out is inside this period, so
  # its catch-up asks the whole $600. Σ $1,200; $150 typed leaves $1,050.
  describe "a fund with a bill beside it" do
    before do
      car = create(:category, :expense, user: user, name: "Car")
      create(:rule, category: car, amount: 2_400, anchor_date: Date.current + 55.days, starts_on: Date.current)
      create(
        :rule,
        category: car,
        item: create(:item, category: car, name: "Insurance"),
        amount: 600,
        interval_months: 1,
        anchor_date: Date.current + 3.days,
        starts_on: Date.current,
        rule_type: :bill
      )

      visit new_entry_path
      select_category("Car")
    end

    # The sharper word wins on a mixed category: money that has to be there on a day somebody else
    # set is a bill, over a category that also carries a target.
    it "keeps the fund shape and drops the ceiling", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='bill']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("title")).to have_text("Car bill")
        expect(figure("balance")).to have_text("$1,200.00")
        expect(figure("balance-after")).to have_text("$1,050.00")
        expect(figure("target")).to have_text("built up")
        expect(page).to have_no_content("of $2,400.00")
      end
    end
  end

  # A dated bill is a fund on this card: the money is demonstrably being saved up toward a day.
  # $600 due three days out is inside this period, so `periods_left` is 1 and the catch-up asks the
  # whole $600 now. $150 typed leaves $450.
  describe "a category whose only rule is a dated bill" do
    before do
      house = create(:category, :expense, user: user, name: "House Deposit")
      create(:rule, category: house, amount: 600, interval_months: 1, anchor_date: Date.current + 3.days, starts_on: Date.current)

      visit new_entry_path
      select_category("House Deposit")
    end

    it "takes the fund shape and measures against the bill", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='target']")
      fill_in "Amount", with: "150"

      within(card) do
        expect(figure("title")).to have_text("House Deposit target")
        expect(figure("balance-after")).to have_text("$450.00")
        expect(figure("target")).to have_text("of $600.00")
        expect(page).to have_no_content("left")
      end
    end
  end

  describe "editing an entry the claim has already counted" do
    let!(:existing) do
      create(:entry, item: weekly_shop, amount: 45, date: Date.current)
    end

    before { visit edit_entry_path(existing) }

    # The claim is $195 — a $300 rate less the fixture's $60 and this $45. The card says $240,
    # because the question on the screen is what this entry costs, not what the last one did.
    it "opens on the world without this entry, then puts it back", :aggregate_failures do
      expect(page).to have_css("[data-impact-card='rules']")

      expect(groceries.rules.sole.claim_calculator.claim).to eq(BigDecimal("195"))
      within(card) do
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("$195.00")
      end
    end

    it "moves the right-hand figure as the amount is edited", :aggregate_failures do
      fill_in "Amount", with: "100"
      within(card) { expect(figure("balance-after")).to have_text("$140.00") }

      fill_in "Amount", with: "10"
      within(card) { expect(figure("balance-after")).to have_text("$230.00") }
    end

    # The figures differ from the create case on the same category and the same amount, which is
    # the whole of what the exclusion is for.
    it "differs from logging the same amount as a new entry", :aggregate_failures do
      visit new_entry_path
      select_category("Groceries")
      fill_in "Amount", with: "45"

      within(card) do
        expect(figure("balance")).to have_text("$195.00")
        expect(figure("balance-after")).to have_text("$150.00")
      end
    end

    it "credits a different category with nothing when the category is changed", :aggregate_failures do
      dining = create(:category, :expense, user: user, name: "Dining Out")
      create(:rule, :rate, category: dining, amount: 100)
      visit edit_entry_path(existing)

      select_category("Dining Out")

      within(card) do
        expect(figure("title")).to have_text("Dining Out rules")
        expect(figure("balance")).to have_text("$100.00")
        expect(figure("balance-after")).to have_text("$55.00")
      end
    end
  end

  describe "editing an entry that already overdraws its category" do
    let!(:existing) do
      create(:entry, item: weekly_shop, amount: 300, date: Date.current)
    end

    it "opens on the negative figure and on 'Save anyway'", :aggregate_failures do
      visit edit_entry_path(existing)

      expect(page).to have_css("[data-impact-card='rules']")
      within(card) do
        expect(figure("balance")).to have_text("$240.00")
        expect(figure("balance-after")).to have_text("-$60.00")
        expect(figure("overdraw")).to be_visible
      end
      expect(page).to have_button("Save anyway")
      expect(page).not_to have_button("Update Entry")
    end

    it "goes back to the ordinary label once the amount fits", :aggregate_failures do
      visit edit_entry_path(existing)
      expect(page).to have_button("Save anyway")

      fill_in "Amount", with: "55"

      within(card) { expect(figure("balance-after")).to have_text("$185.00") }
      expect(page).to have_button("Update Entry")
      expect(page).not_to have_button("Save anyway")
    end
  end
end
