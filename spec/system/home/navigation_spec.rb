# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Navigation", type: :system do
  let(:user) { create(:user, :biweekly) }

  before { sign_in user, scope: :user }

  it "lands on Home at the root" do
    visit root_path

    expect(page).to have_css("h1", text: "Home")
  end

  it "keeps the dashboard reachable as Reports", :aggregate_failures do
    visit reports_path

    expect(page).to have_current_path(reports_path)
    expect(page).to have_css("h1", text: "Reports")
  end

  it "lists Reports in the sidebar" do
    visit root_path

    expect(page).to have_link("Reports", href: reports_path)
  end

  # The negative half of each rename. Capybara.exact is unset in this project, so link
  # text matches by substring: have_link("Pools") passes just as happily against
  # "Savings Pools", and the positive assertions alone would survive a full revert.
  it "replaces the old entries rather than adding to them", :aggregate_failures do
    visit root_path

    expect(page).to have_link("Home", href: root_path)
    expect(page).to have_no_link("Dashboard")
    # THE "Pools" ITEM IS GONE (two-ledger spec §5, Task 7): it opened the savings-goals index,
    # and a savings goal is a CATEGORY now, so the Management section has one link.
    expect(page).to have_link("Categories", href: categories_path)
    expect(page).to have_no_link("Pools")
    expect(page).to have_no_link("Savings Pools")
    expect(page).to have_no_link("Statistics")
  end

  # ──────────────────────────────────────────────────────────────────────────────────────────
  # THE WAY IN TO THE DISTRIBUTION SCREEN. Until these links existed, `new_distribution_path`
  # appeared nowhere in `app/` outside the distributions controller and its own views: the
  # headline feature of this plan shipped dark and the only way to split a paycheck was to type
  # the URL. Home even printed "the next distribution funds this in full" over no way to reach it.
  #
  # Both entry points are asserted, and both are asserted to ARRIVE — a link whose href is right
  # and whose destination 404s or bounces to Home would satisfy `have_link` on its own.
  describe "reaching the distribution screen" do
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    # TWO LEDGERS, TWO FIXTURES, until Task 6 makes Home's rows categories (two-ledger spec §2).
    # The POOL envelope is what Home's own waterfall band renders — the band carrying the second
    # link asserted below — and the holder CATEGORY is what `/distributions/new` fills, since the
    # distribution screen reads `Category.in_fill_order` now. Planted with the same $400 rule so the
    # two screens describe the same shortfall; without the category the screen this file navigates
    # TO renders no waterfall at all and "Where your money goes" is simply absent.
    before do
      rent = create(:pool, :budget_pool, user: user, account: checking, name: "Rent", priority: 1)
      create(:pool_budget, :per_period_rate, pool: rent, amount: 400)
      groceries = create(:category, :expense, :funded, user: user, name: "Groceries", priority: 1)
      create(:budget, :per_period_rate, pool: nil, category: groceries, amount: 400)
      category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: category), amount: 100, date: Date.current)
      visit root_path
    end

    def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

    # `exact_text` because Capybara.exact is unset and Home's own band link reads "Distribute
    # this period" — a bare "Distribute" matches both, and the click below would be ambiguous.
    def nav_link = find_link("Distribute", exact_text: true)

    # `have_link(href:)` rather than reading `[:href]` off the node: selenium hands back the
    # resolved absolute URL, so the raw attribute is never the path this route names.
    it "offers Distribute in the sidebar, and it goes somewhere real", :aggregate_failures do
      expect(page).to have_link("Distribute", href: new_distribution_path)

      nav_link.click

      expect(page).to have_current_path(new_distribution_path)
      expect(page).to have_css("h1", text: "Distribution")
      expect(page).to have_content("Where your money goes")
    end

    # The band that has just told the user where this period's money goes is the other place the
    # action belongs — a user reading "the next distribution funds this in full" is one click away
    # from performing it.
    it "offers the same action from the band that describes it", :aggregate_failures do
      within(waterfall_section) { click_link "Distribute this period" }

      expect(page).to have_current_path(new_distribution_path)
      expect(page).to have_css("h1", text: "Distribution")
    end

    # `/distributions/new` is a GET that takes WRITE LOCKS: DistributionPresenter's snapshot
    # deletes this period's split, holds the row locks on both pools of every deleted row for the
    # whole snapshot (~320ms measured), and rolls back. turbo-rails prefetches links on hover by
    # default, so without this a hover would fire it. Asserted on both links, because either one
    # left unmarked is the whole hazard back.
    it "keeps turbo from prefetching either link", :aggregate_failures do
      expect(nav_link["data-turbo-prefetch"]).to eq("false")
      band_link = within(waterfall_section) { find_link("Distribute this period") }
      expect(band_link["data-turbo-prefetch"]).to eq("false")
    end
  end
end
