# frozen_string_literal: true

require "rails_helper"

# THE GOALS STRIP, WHICH IS NOW ON THE ALL TAB AND ONLY THERE (plan 3, task 5). It was rendered by
# both tabs; the savings TAB is deleted with the category type it summed, and the strip's two
# readers moved from `Dashboard::SavingsPresenter` to `Dashboard::OverviewPresenter` rather than
# dying with it — the strip is POOL-type machinery, and the pool type survives.
#
# EVERY FIXTURE HERE FUNDS ITS POOL WITH MOVEMENTS. They funded it with entries in a savings
# CATEGORY, which is the shape the cutover converted; the balances asserted are unchanged, because
# `PoolCalculator#balance` counted that term and counts `movements_in` at the same sign.
RSpec.describe "Dashboard Index - Savings Pools", type: :system do
  let!(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  def goal(name, target)
    create(:pool, user: user, name: name, target_amount: target, start_date: 1.year.ago, account: checking)
  end

  def fund(pool, amount, on)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  # One category per pool, reused across calls: Category validates its name unique per user, so a
  # pool spent from twice would otherwise collide with itself.
  def spend(pool, amount, on)
    category = user.categories.find_by(name: "#{pool.name} Spending") ||
               create(:category, :expense, user: user, name: "#{pool.name} Spending", pool: pool)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  describe "pool balance reflects selected month", :aggregate_failures do
    let!(:pool) { goal("Vacation Fund", 5_000) }

    before do
      # Previous month: $800 in, $200 out => balance $600
      fund(pool, 800.00, base_date - 1.month + 1.day)
      spend(pool, 200.00, base_date - 1.month + 5.days)

      # Current month: $500 in, $100 out => cumulative balance $1,000
      fund(pool, 500.00, base_date + 1.day)
      spend(pool, 100.00, base_date + 5.days)
    end

    it "shows the pool's balance on the All tab" do
      visit reports_path

      within(find("a[href='#{pool_path(pool)}']")) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00") # 1300 - 300
      end
    end

    # THE PER-PERIOD "In / Out" ROW IS DELETED (plan 3, task 4), and the example that read it goes
    # with the behaviour. "In" was `Pool#contribution_entries` — savings-TYPED entries — so on the
    # post-cutover demo it printed $0.00 on every card while those goals were receiving $525 a
    # period as PoolMovements.
    it "shows the card's balance against its target, and no per-period flow" do
      visit reports_path

      within(find("a[href='#{pool_path(pool)}']")) do
        expect(page).to have_content("$1,000.00")
        expect(page).to have_content("of $5,000.00")
        expect(page).to have_no_content("In")
        expect(page).to have_no_content("Out")
      end
    end

    # BOTH DIRECTIONS ON THE TAB THAT IS GONE. `?tab=savings` is a stale bookmark now, and
    # DashboardController checks the parameter against its own list rather than trusting it — so it
    # lands on All, which still renders this strip, instead of on an empty panel under a tab strip.
    it "is still reached by a stale ?tab=savings bookmark, which lands on All", :aggregate_failures do
      visit reports_path(tab: "savings")

      expect(page).to have_no_link("Savings")
      expect(find("nav[aria-label='Tabs'] a", text: "All")[:class]).to include("border-brand")
      within(find("a[href='#{pool_path(pool)}']")) { expect(page).to have_content("$1,000.00") }
    end
  end

  describe "total pools balance", :aggregate_failures do
    let!(:pool_a) { goal("Pool A", 5_000) }
    let!(:pool_b) { goal("Pool B", 3_000) }

    before do
      fund(pool_a, 1_000.00, base_date + 1.day)
      fund(pool_b, 500.00, base_date + 1.day)
    end

    it "shows combined total across all pools" do
      visit reports_path

      expect(page).to have_content("Total:")
      expect(page).to have_content("$1,500.00")
    end
  end

  describe "status badges", :aggregate_failures do
    it "shows 'funded' badge when pool reaches 100%" do
      pool = goal("Small Goal", 100)
      fund(pool, 100.00, base_date + 1.day)

      visit reports_path

      within(find("a[href='#{pool_path(pool)}']")) { expect(page).to have_content("funded") }
    end

    it "shows 'low' badge when pool is under 10%" do
      pool = goal("Big Goal", 10_000)
      fund(pool, 50.00, base_date + 1.day)

      visit reports_path

      within(find("a[href='#{pool_path(pool)}']")) { expect(page).to have_content("low") }
    end

    it "shows 'negative' badge when spending exceeds what was moved in" do
      pool = goal("Depleted Fund", 5_000)
      fund(pool, 100.00, base_date + 1.day)
      spend(pool, 500.00, base_date + 2.days)

      visit reports_path

      within(find("a[href='#{pool_path(pool)}']")) { expect(page).to have_content("negative") }
    end
  end
end
