# frozen_string_literal: true

require "rails_helper"

# The screen that answers "what would have to give" when reallocation cannot help, and the dial that
# answers it live.
#
# Every fixture here is biweekly, so a rolling bill's amount and its per-period claim are never the
# same number: a suite of per-period rules would pass with a mixed-unit slip in place. Income is
# measured over the two complete periods behind Sep 9 (Aug 7 – Aug 20 and Aug 21 – Sep 3), which is
# why the fixture earns twice.
#
# `Capybara.exact` is unset in this suite, so every figure is scoped to its own `data-figure` or its
# own row: unscoped, "$1,000.00" matches the income line from inside the totals block.
RSpec.describe "Sacrifice view", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each do |on|
      create(:entry, item: create(:item, category: salary), amount: 1_000, date: on)
    end
  end

  def category(name) = create(:category, user: user, name: name)

  # Anchorless per-period: a rate, and cuttable.
  def rate_rule(name, amount)
    create(:rule, :rate, category: category(name), amount: amount, starts_on: Date.new(2026, 1, 1))
  end

  # Anchored and repeating: a bill somebody else sets, and fixed. $600 every 6 months claims
  # `600 × 12 ÷ (26 × 6)` = $46.15 of a biweekly period — nothing like its own amount.
  def rolling_rule(name, amount)
    create(
      :rule,
      :bill,
      category: category(name),
      amount: amount,
      interval_months: 6,
      anchor_date: Date.new(2026, 10, 1),
      starts_on: Date.new(2026, 1, 1)
    )
  end

  def figure(name) = find("[data-figure='#{name}']")
  def row(rule) = find("[data-sacrifice-row='#{rule.id}']")

  # Edit opens the row (a no-op under Rack::Test, where every input is already live).
  def cut(rule, label, to:)
    within(row(rule)) do
      click_button "Edit #{label}"
      fill_in "Cut #{label} to", with: to
    end
  end

  # $800 of groceries, $300 of fun and a $600-every-6-months insurance that claims $46.15 of a
  # biweekly period: $1,146.15 of rules against $1,000 of income, a gap of $146.15 that the $1,100 of
  # rate rules can close several times over.
  def winnable
    { groceries: rate_rule("Groceries", 800), fun: rate_rule("Fun", 300), insurance: rolling_rule("Insurance", 600) }
  end

  describe "a budget the cuts could close" do
    let(:rules) { winnable }

    before do
      rules
      visit sacrifice_path
    end

    # The gap, then the two figures it came from — the same two the Budget page's tiles print, so a
    # user arriving from that button meets the number they just read.
    it "opens on the gap and the figures behind it", :aggregate_failures do
      expect(figure("gap")).to have_content("$146.15 underwater every period")
      expect(figure("budget")).to have_content("$1,146.15")
      expect(figure("typical-income")).to have_content("$1,000.00")
    end

    # No false comfort cuts both ways: printing the unwinnable sentence on a budget the user CAN fix
    # would be its own kind of lie.
    it "says nothing about being unwinnable" do
      expect(page).to have_no_css("[data-unwinnable]")
    end

    # The stated order and the order itself, together: biggest claim first, which is neither
    # alphabetical nor the order the rules were written in.
    it "says the biggest claim is first, and lists them that way", :aggregate_failures do
      expect(find("[data-cut-list-order]")).to have_content("The biggest claim is first")
      expect(page.all("[data-sacrifice-row]").pluck("data-sacrifice-row"))
        .to eq([rules.fetch(:groceries).id, rules.fetch(:fun).id])
      expect(page.all("[data-fixed-row]").pluck("data-fixed-row")).to eq([rules.fetch(:insurance).id])
    end

    # A repeating bill is listed rather than hidden, because the gap at the top of the page is made of
    # it too — with its own unit beside the per-period claim, so the edit form it links to is not a
    # surprise.
    it "marks the bill it will not pretend is optional", :aggregate_failures do
      within("[data-fixed-row='#{rules.fetch(:insurance).id}']") do
        expect(page).to have_css("[data-role='claim']", text: "$46.15 a period")
        expect(page).to have_css("[data-role='claim']", text: "$600.00 every 6 months")
        expect(page).to have_css("[data-role='fixed-reason']", text: "fixed — the bill is what it is")
      end
    end

    it "opens with nothing cut and the whole gap still open", :aggregate_failures do
      expect(figure("frees")).to have_content("$0.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $146.15 a period")
    end

    # The input IS the edit on a cuttable row, so the link that used to send it elsewhere is gone;
    # a rolling bill still needs its own form, so its row keeps the link.
    it "keeps the edit link only on the row it cannot dial", :aggregate_failures do
      expect(row(rules.fetch(:groceries))).to have_no_link("Edit the rule")
      expect(row(rules.fetch(:fun))).to have_no_link("Edit the rule")
      expect(find("[data-fixed-row='#{rules.fetch(:insurance).id}']")).to have_link("Edit the rule")
    end

    it "says saving writes the cuts to the rules", :aggregate_failures do
      order = find("[data-cut-list-order]")
      expect(order).to have_content("Save writes the rules you dialled down")
      expect(order).to have_content("delete it on the Budget page")
    end
  end

  # The dial through the browser: two cuts, and the totals read at each step. $800 cut to $700 frees
  # $100, $300 cut to nothing frees $300, and the $146.15 gap closes into $253.85 to spare.
  describe "the dial", :js do
    let(:rules) { winnable }

    before do
      rules
      visit sacrifice_path
    end

    it "recomputes the totals as cuts are dialled in", :aggregate_failures do
      cut(rules.fetch(:groceries), "Groceries", to: "700")

      expect(figure("frees")).to have_content("$100.00 a period")
      expect(figure("verdict")).to have_content("Still underwater $46.15 a period")

      cut(rules.fetch(:fun), "Fun", to: "0")

      expect(figure("frees")).to have_content("$400.00 a period")
      expect(figure("verdict")).to have_content("Covered — $253.85 a period to spare")
    end

    # Each row says what its own cut frees, because the footer's total cannot say which of several
    # dialled rows produced it. Typing the claim back is the undo.
    it "says what each row frees, and frees nothing once the figure is typed back", :aggregate_failures do
      cut(rules.fetch(:groceries), "Groceries", to: "700")

      expect(row(rules.fetch(:groceries))).to have_css("[data-role='row-frees']", text: "frees $100.00")

      within(row(rules.fetch(:groceries))) { fill_in "Cut Groceries to", with: "800" }

      expect(row(rules.fetch(:groceries))).to have_css("[data-role='row-frees']", text: "frees $0.00")
    end
  end

  # The cut you dial is the edit: saving writes it to the rule and lands wherever the fresh gap
  # sends the page.
  describe "saving the cuts" do
    let(:rules) { winnable }

    before do
      rules
      visit sacrifice_path
    end

    it "writes the dialled cut and lands on Budget once it closes the gap", :aggregate_failures do
      cut(rules.fetch(:groceries), "Groceries", to: "500")
      click_button "Save these cuts"

      expect(page).to have_content("Saved — 1 cut. Your savings and budget now need $846.15 a period.")
      expect(rules.fetch(:groceries).reload.amount).to eq(500)
    end

    it "disables the save button until a row is dialled down", :aggregate_failures, :js do
      expect(page).to have_button("Save these cuts", disabled: true)

      cut(rules.fetch(:groceries), "Groceries", to: "700")

      expect(page).to have_button("Save these cuts", disabled: false)
    end

    # A row opens read-only; Undo puts the claim back, closes it, and takes it out of the save.
    it "keeps a row read-only until Edit, and Undo takes it back out", :aggregate_failures, :js do
      groceries = rules.fetch(:groceries)
      expect(row(groceries)).to have_field("Cut Groceries to", disabled: true)

      cut(groceries, "Groceries", to: "700")
      expect(row(groceries)).to have_css("[data-role='row-frees']", text: "frees $100.00")

      within(row(groceries)) { click_button "Undo Groceries" }

      expect(row(groceries)).to have_field("Cut Groceries to", disabled: true, with: "800.00")
      expect(row(groceries)).to have_css("[data-role='row-frees']", text: "frees $0.00")
      expect(page).to have_button("Save these cuts", disabled: true)
    end
  end

  # Savings targets get their own section: a fixed target is cut by amount, a share by percent, and
  # both save through SacrificeCuts alongside any rule cuts.
  describe "savings targets" do
    let(:emergency) { create(:account, user: user, name: "Emergency") }
    let(:paycheck) { create(:item, :income, category: salary, name: "Paycheck") }
    let(:fun) { rate_rule("Fun", 300) }

    before do
      fun
      create(:rule, :rolling, :bill, category: category("Rent"), amount: 2_000, anchor_date: Date.new(2026, 10, 1), interval_months: 1, starts_on: Date.new(2026, 1, 1))
    end

    context "with a fixed and a share target" do
      before do
        [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: paycheck, amount: 500, date: on) }
        create(:savings_target, account: emergency, amount: 400, starts_on: Date.new(2026, 9, 4))
        create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 9, 4))
        visit sacrifice_path
      end

      it "lists each savings target in its own section and dials a share by percent", :aggregate_failures, :js do
        expect(page).to have_css("[data-figure='savings']", text: "$450.00")
        within("[data-sacrifice-target='#{SavingsTarget.shares.sole.id}']") do
          expect(page).to have_content("Emergency · 10% of Paycheck")
          expect(page).to have_css("[data-role='claim']", text: "$50.00 a period")
          find("input[type='checkbox']").check
          find("input[name='target_cuts[#{SavingsTarget.shares.sole.id}]']").fill_in(with: "6")
          expect(page).to have_css("[data-role='row-frees']", text: "frees $20.00")
        end
        expect(page).to have_css("[data-figure='frees']", text: "$20.00 a period")
      end

      # A row's input is disabled while its checkbox is unticked, so a figure typed in and then
      # unticked can never reach the server — the dial's freed figure and the write agree.
      it "keeps an edited-but-unticked target row's figure when the cuts are saved", :aggregate_failures, :js do
        fixed = SavingsTarget.fixed.sole
        cut(fun, "Fun", to: "200")

        within("[data-sacrifice-target='#{fixed.id}']") do
          find("input[type='checkbox']").check
          find("input[name='target_cuts[#{fixed.id}]']").fill_in(with: "100")
          find("input[type='checkbox']").uncheck
        end
        click_button "Save these cuts"

        expect(page).to have_content("Saved")
        expect(fixed.reload.amount).to eq(400)
      end
    end

    it "saves a target cut", :aggregate_failures do
      fixed = create(:savings_target, account: emergency, amount: 400, starts_on: Date.new(2026, 9, 4))

      visit sacrifice_path
      find("input[name='target_cuts[#{fixed.id}]']").fill_in(with: "250")
      click_button "Save these cuts"

      expect(page).to have_content("Saved — 1 cut.")
      expect(fixed.reload.amount).to eq(250)
    end
  end

  # The page refuses in exactly the two states the Budget page's button is not shown in, so the
  # route's gate and the tile's are one condition read twice.
  describe "the two states this page refuses", :aggregate_failures do
    it "sends a budget that already fits back to the Budget page" do
      rate_rule("Groceries", 100)

      visit sacrifice_path

      expect(page).to have_content("Your savings and budget already fit what you bring in")
      expect(page).to have_css("[data-tiles]")
    end

    it "sends a user with no period or no history back to set one" do
      undeclared = create(:user)
      create(:account, user: undeclared)
      sign_in undeclared, scope: :user

      visit sacrifice_path

      expect(page).to have_content("Set your period on the Budget page")
      expect(page).to have_css("[data-tiles]")
    end
  end
end
