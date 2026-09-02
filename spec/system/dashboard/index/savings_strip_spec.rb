# frozen_string_literal: true

require "rails_helper"

# THE GOALS STRIP, WHICH IS NOW ON THE ALL TAB AND ONLY THERE (plan 3, task 5), AND WHICH IS NOW
# ABOUT CATEGORIES (two-ledger spec §3, Task 7).
#
# THE FIXTURES ARE THE MODEL CHANGE. They planted savings POOLS funded by `AccountMovement`s and
# spent by categories pointing at them; a savings goal is a CATEGORY now — a target, a funding
# start and no refill rule (`Category#savings?`, which is exactly what Task 1's migration mints out
# of a savings pool) — funded by `Allocation`s and spent by its own entries. Every balance and
# every badge asserted below is unchanged, because `HoldingCalculator#balance` counts allocations
# in and spending out at the same signs `PoolCalculator` did.
#
# THE LINKS POINT AT THE CATEGORY, because the pool page is deleted and the category's own page is
# where a goal's balance, target and history all live now.
RSpec.describe "Dashboard Index - Savings strip", type: :system do
  let!(:user) { create(:user) }
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST for the category factory's own `pool`
  # default, which still names a pool for the length of this branch. Nothing on the strip reads it;
  # it was funded FROM until Task 7 replaced the movements with allocations.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  # A GOAL: an expense category with a target, holding money from a year back, carrying no rule.
  def goal(name, target)
    create(
      :category,
      :expense,
      user: user,
      name: name,
      target_amount: target,
      funded_since: 1.year.ago.to_date
    )
  end

  def fund(category, amount, on)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: on)
  end

  # One item per category, reused across calls, so a goal spent from twice does not collide with
  # itself on Item's per-category name uniqueness.
  def spend(category, amount, on)
    item = category.items.find_by(name: "Spending") || create(:item, category: category, name: "Spending")
    create(:entry, item: item, amount: amount, date: on)
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

      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00") # 1300 - 300
      end
    end

    # THE PER-PERIOD "In / Out" ROW IS DELETED (plan 3, task 4), and the example that read it goes
    # with the behaviour. "In" was `Pool#contribution_entries` — savings-TYPED entries — so on the
    # post-cutover demo it printed $0.00 on every card while those goals were visibly receiving
    # $525 a period.
    it "shows the card's balance against its target, and no per-period flow" do
      visit reports_path

      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) do
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
      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) { expect(page).to have_content("$1,000.00") }
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

      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) { expect(page).to have_content("funded") }
    end

    it "shows 'low' badge when pool is under 10%" do
      pool = goal("Big Goal", 10_000)
      fund(pool, 50.00, base_date + 1.day)

      visit reports_path

      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) { expect(page).to have_content("low") }
    end

    it "shows 'negative' badge when spending exceeds what was moved in" do
      pool = goal("Depleted Fund", 5_000)
      fund(pool, 100.00, base_date + 1.day)
      spend(pool, 500.00, base_date + 2.days)

      visit reports_path

      within(find("[data-savings-strip] a[href='#{category_path(pool)}']")) { expect(page).to have_content("negative") }
    end
  end
end
