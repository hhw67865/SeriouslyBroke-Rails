# frozen_string_literal: true

require "rails_helper"

# Which income categories feed typical income, chosen from the Budget page's declare view.
RSpec.describe "Budget page income categories", type: :system do
  let(:user) { create(:user, :biweekly) }
  let!(:salary) { create(:category, :income, user: user, name: "Salary") }
  let!(:bonus) { create(:category, :income, :irregular, user: user, name: "Bonus") }

  before { sign_in user, scope: :user }

  it "shows a checkbox per income category, checked to match `regular`", :aggregate_failures do
    visit budget_page_path(declare: 1)

    within("[data-income-categories-section]") do
      expect(page).to have_field(salary.name, checked: true)
      expect(page).to have_field(bonus.name, checked: false)
    end
  end

  it "saves the chosen categories and re-derives which ones are regular", :aggregate_failures do
    visit budget_page_path(declare: 1)

    within("[data-income-categories-section]") do
      uncheck salary.name
      check bonus.name
      click_button "Save income categories"
    end

    expect(page).to have_content("your typical income is measured from those categories now")
    expect(salary.reload).not_to be_regular
    expect(bonus.reload).to be_regular
  end

  it "invites adding an income category when there are none", :aggregate_failures do
    salary.destroy!
    bonus.destroy!

    visit budget_page_path(declare: 1)

    within("[data-income-categories-section]") do
      expect(page).to have_content("You have no income categories yet.")
      expect(page).to have_link("Add one", href: new_category_path(type: "income"))
    end
  end

  it "links from the income tile to which categories count, once a period is declared" do
    create(:account, user: user)

    visit budget_page_path

    expect(tile("income")).to have_link("which categories count", href: budget_page_path(declare: 1))
  end

  def tile(name) = find("[data-tile='#{name}']")
end
