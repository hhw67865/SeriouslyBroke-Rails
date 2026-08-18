# frozen_string_literal: true

require "rails_helper"

# THE TIMELINE, CONVERTED TO MOVEMENTS (plan 3, task 5).
#
# It listed savings-typed entries as contributions and expense-typed ones as withdrawals. The
# savings category is gone, so the contributing half selected NOTHING and every goal's history
# rendered empty beside a "Total Contributions" tile printing real money — the defect Task 2
# recorded and the `TODO(plan-3)` on `Pool#contribution_entries` predicted. `Pool#timeline` is one
# reader: `movements_in`/`movements_out`, which IS the post-cutover contribution history, plus the
# spending of the categories pointing at this pool. Those are exactly the rows the two tiles above
# the list add up.
RSpec.describe "Savings Pools Show - Recent Activity", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, account: checking) }
  let!(:expense_category) { create(:category, user: user, name: "Emergency Withdrawal", category_type: :expense, pool: pool) }

  before { sign_in user, scope: :user }

  def contribute(amount, on)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first

  describe "with a history", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category, name: "Medical Bill") }

    before do
      contribute(500.0, Date.current)
      create(:entry, item: expense_item, amount: 150.0, date: Date.current - 1.day)
      contribute(300.0, Date.current - 2.days)

      visit pool_path(pool)
    end

    it "shows recent activity section" do
      expect(page).to have_content("Recent Activity")
      expect(page).to have_content("Last 8 movements and entries")
    end

    it "links to the spending it can show, and says so" do
      activity_header = page.all("div.flex.items-center.justify-between", text: "Recent Activity").first
      within(activity_header) do
        expect(page).to have_link("Show all spending")
        click_link "Show all spending"
      end

      expect(page).to have_current_path(entries_path(field: "pool", q: pool.name))
    end

    # A MOVEMENT'S ROW NAMES THE POOL AT THE OTHER END; an entry's names its item. That is the
    # difference the conversion introduces, and it is the useful half — "where did this money come
    # from" is the question a goal's history answers.
    it "names the counterpart pool for a movement and the item for an entry" do
      within(activity_section) do
        expect(page).to have_content("Checking")
        expect(page).to have_content("Medical Bill")
      end
    end

    it "shows correct amounts with signs" do
      within(activity_section) do
        expect(page).to have_content("+$500.00")
        expect(page).to have_content("-$150.00")
        expect(page).to have_content("+$300.00")
      end
    end

    it "labels each row by what it is, in both directions" do
      within(activity_section) do
        expect(page).to have_css(".bg-status-success-light.text-status-success", text: "Moved in")
        expect(page).to have_css(".bg-status-danger-light.text-status-danger", text: "Spent")
        expect(page).to have_no_content("Savings")
      end
    end

    it "says how a movement was made, and which category an entry came from" do
      within(activity_section) do
        expect(page).to have_content("moved by hand")
        expect(page).to have_content("Emergency Withdrawal")
      end
    end

    it "displays row dates" do
      within(activity_section) do
        expect(page).to have_content(Date.current.strftime("%b %d, %Y"))
        expect(page).to have_content((Date.current - 1.day).strftime("%b %d, %Y"))
      end
    end
  end

  describe "money leaving the pool", :aggregate_failures do
    before do
      contribute(400.0, Date.current - 1.day)
      create(:pool_movement, from_pool: pool, to_pool: checking, amount: 90.0, date: Date.current)

      visit pool_path(pool)
    end

    # THE OTHER MOVEMENT DIRECTION, which the old timeline had no row shape for at all: it read
    # entries only, so money transferred back out of a goal appeared nowhere.
    it "shows a movement out as a negative row labelled Moved out" do
      within(activity_section) do
        expect(page).to have_css("[data-timeline-row='out']", text: "Moved out")
        expect(page).to have_content("-$90.00")
        expect(page).to have_css("[data-timeline-row='in']", text: "Moved in")
        expect(page).to have_content("+$400.00")
      end
    end
  end

  describe "with many rows", :aggregate_failures do
    before do
      # Create 10 movements, but only 8 should be displayed
      10.times { |i| contribute(100.0, Date.current - i.days) }

      visit pool_path(pool)
    end

    it "shows only the 8 most recent rows" do
      expect(page.all("div.bg-gray-50.rounded").count).to eq(8)
    end

    it "shows rows in descending date order" do
      within(activity_section) do
        dates = page.all("div.bg-gray-50.rounded div.text-right div.text-xs.text-gray-500").map(&:text)
        expect(dates.first).to include(Date.current.strftime("%b %d, %Y"))
        expect(dates.last).to include((Date.current - 7.days).strftime("%b %d, %Y"))
      end
    end
  end

  describe "with nothing at all" do
    before { visit pool_path(pool) }

    it "does not show recent activity header" do
      expect(page).not_to have_content("Recent Activity")
    end

    it "does not show the row count label" do
      expect(page).not_to have_content("Last 8 movements and entries")
    end
  end
end
