# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Income Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit reports_path(tab: "income") }

    it "shows empty message when no income data" do
      expect(page).to have_content("No income data available")
      expect(page).to have_content("No income recorded")
    end
  end

  describe "with income data", :aggregate_failures do
    let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
    let!(:income_item) { create(:item, category: income_category, name: "Paycheck") }

    before do
      create(:entry, item: income_item, amount: 3000.00, date: base_date + 1.day)
      create(:entry, item: income_item, amount: 2800.00, date: base_date - 1.month + 1.day)
      visit reports_path(tab: "income")
    end

    it "shows income chart heading" do
      expect(page).to have_content("Income by Category")
      expect(page).to have_content("6 months")
    end

    it "shows tracked and total income summary stats" do
      within_stat_card("Tracked Income") { expect(page).to have_content("$3,000.00") }
      within_stat_card("Total Income") { expect(page).to have_content("$3,000.00") }
    end

    # ** AN ACCOUNT'S OPENING RECORD IS NOT INCOME THE HOUSEHOLD RECEIVED (fix round 3 — R5). ** It
    # is an INCOME entry when the account holds money — that is how the figure enters the ledger,
    # and `AccountLedger` must go on counting it or `pot + Σ accounts == income − expenses` breaks —
    # but on THIS page it was $500 somebody said was in their savings account reported as money they
    # earned. A NEW user's opening day is the day before their earliest entry, so for a household
    # setting up today it lands inside the current period, which is exactly this card. Both
    # directions on one fixture: the $3,000 paycheck is still there and the $500 opening is not.
    # The opening record as `AccountOpening` writes one: the entry, its marker, and the category the
    # service reserves for it.
    def plant_an_opening(amount)
      account = create(:pool, :account, user: user, name: "Checking")
      item = create(:item, category: create(:category, :opening_balance, user: user), name: "Initial balance")
      create(:entry, item: item, amount: amount, date: base_date + 1.day, opening_account: account)
    end

    it "leaves an account's opening record out of the income figures", :aggregate_failures do
      plant_an_opening(500)

      visit reports_path(tab: "income")

      within_stat_card("Total Income") { expect(page).to have_content("$3,000.00") }
      within_stat_card("Total Income") { expect(page).to have_no_content("$3,500.00") }
      expect(page).to have_no_content(Category::OPENING_BALANCE_NAME)
    end

    it "shows vs Last Month percentage change" do
      expect(page).to have_content("vs Last Month")
      expect(page).to have_content("+7%")
    end

    it "shows category breakdown with linked categories" do
      expect(page).to have_content("By Category")
      expect(page).to have_link("Salary", href: category_path(income_category))
      expect(page).to have_content("$3,000.00")
    end
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:salary) { create(:category, :income, user: user, name: "Salary") }
    let!(:salary_item) { create(:item, category: salary, name: "Paycheck") }
    let!(:freelance) { create(:category, :income, user: user, name: "Freelance", tracked: false) }
    let!(:freelance_item) { create(:item, category: freelance, name: "Project") }

    before do
      create(:entry, item: salary_item, amount: 5000.00, date: base_date + 1.day)
      create(:entry, item: freelance_item, amount: 1000.00, date: base_date + 2.days)
      visit reports_path(tab: "income")
    end

    it "shows tracked and untracked categories separately with links" do
      within_stat_card("Tracked Income") { expect(page).to have_content("$5,000.00") }
      within_stat_card("Total Income") { expect(page).to have_content("$6,000.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Salary", href: category_path(salary))
      expect(page).to have_link("Freelance", href: category_path(freelance))
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:income_category) { create(:category, :income, user: user, name: "Freelance") }
    let!(:income_item) { create(:item, category: income_category, name: "Project") }

    before do
      create(:entry, item: income_item, amount: 1500.00, date: base_date)
      create(:entry, item: income_item, amount: 2000.00, date: base_date - 1.month)
      visit reports_path(tab: "income", period: "ytd")
    end

    it "shows YTD in chart heading" do
      expect(page).to have_content("Income by Category")
      expect(page).to have_content("YTD")
    end

    it "shows YTD Tracked label in summary stats" do
      expect(page).to have_content("YTD Tracked")
    end

    it "does not show vs Last Month in YTD view" do
      expect(page).not_to have_content("vs Last Month")
    end
  end

  private

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
