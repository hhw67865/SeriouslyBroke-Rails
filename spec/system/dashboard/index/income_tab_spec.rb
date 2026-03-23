# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Income Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit root_path(tab: "income") }

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
      visit root_path(tab: "income")
    end

    it "shows income chart heading" do
      expect(page).to have_content("Income by Category")
      expect(page).to have_content("6 months")
    end

    it "shows tracked and total income summary stats" do
      within_stat_card("Tracked Income") { expect(page).to have_content("$3,000.00") }
      within_stat_card("Total Income") { expect(page).to have_content("$3,000.00") }
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
      visit root_path(tab: "income")
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
      visit root_path(tab: "income", period: "ytd")
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
