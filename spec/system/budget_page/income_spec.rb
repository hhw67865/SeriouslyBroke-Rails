# frozen_string_literal: true

require "rails_helper"

# The period and the income categories, one page, one form.
RSpec.describe "Budget page income", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let!(:salary) { create(:category, :income, user: user, name: "Salary") }
  let!(:bonus) { create(:category, :income, :irregular, user: user, name: "Bonus") }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
  end

  it "goes from Budget's 'change' to Your income" do
    visit budget_page_path
    click_link "change"

    expect(page).to have_current_path(budget_income_path)
  end

  it "shows a checkbox per income category, checked to match `regular`", :aggregate_failures do
    visit budget_income_path

    expect(page).to have_field(salary.name, checked: true)
    expect(page).to have_field(bonus.name, checked: false)
  end

  it "invites adding an income category when there are none", :aggregate_failures do
    salary.destroy!
    bonus.destroy!

    visit budget_income_path

    expect(page).to have_content("You have no income categories yet.")
    expect(page).to have_link("Add one", href: new_category_path(type: "income"))
  end

  # The grid is biweekly anchored 2026-02-06, so Sep 9 sits in Sep 4 – Sep 17 and the two complete
  # periods behind it are Aug 7 – Aug 20 and Aug 21 – Sep 3.
  context "with a history of income" do
    let(:today) { Date.new(2026, 9, 9) }

    around { |example| travel_to(today) { example.run } }

    def earn(category, amount, on:) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

    before { [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| earn(salary, 2_000, on: on) } }

    it "shows what it measured", :aggregate_failures do
      visit budget_income_path

      expect(page).to have_css("[data-figure='typical-income']", text: "$2,000.00")
      expect(page).to have_css("[data-measured-period]", count: 2)
    end

    it "saves the chosen categories and lands on Budget, where the tile shows the new figure", :aggregate_failures do
      { Date.new(2026, 8, 7) => 500, Date.new(2026, 8, 25) => 700 }.each { |on, amount| earn(bonus, amount, on: on) }

      visit budget_income_path

      uncheck salary.name
      check bonus.name
      click_button "Save"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("every figure is re-derived")
      expect(page).to have_css("[data-tile='income'] [data-tile-figure]", text: "$600.00")
      expect(salary.reload).not_to be_regular
      expect(bonus.reload).to be_regular
    end

    # Both categories are regular here, so unticking one is the one interaction that changes the
    # figure without a Save — the frame is the server's own recount, not arithmetic in the browser.
    describe "the live preview", :js do
      before do
        bonus.update!(regular: true)
        [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| earn(bonus, 500, on: on) }
      end

      it "recomputes the typical-income figure as a category is unticked and re-ticked", :aggregate_failures do
        visit budget_income_path

        expect(page).to have_css("[data-figure='typical-income']", text: "$2,500.00")

        uncheck bonus.name

        expect(page).to have_css("[data-figure='typical-income']", text: "$2,000.00")
        expect(bonus.reload).to be_regular

        check bonus.name

        expect(page).to have_css("[data-figure='typical-income']", text: "$2,500.00")
      end
    end
  end
end
