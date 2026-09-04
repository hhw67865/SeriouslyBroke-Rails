# frozen_string_literal: true

require "rails_helper"

# ** THE DISTRIBUTION BLOCK IS DELETED FROM THIS FILE (computed-claims spec §§5-6). ** What stood
# at the foot was `describe "reaching the distribution screen"` — a holder-and-paycheck fixture,
# a `nav_link` helper (`find_link("Distribute", exact_text: true)`) and three examples:
#
#   * "offers Distribute in the sidebar, and it goes somewhere real" — asserted the sidebar link
#     carried `new_distribution_path` AND that clicking it arrived at a page headed "Distribution"
#     saying "Where your money goes". Both halves are false by construction now: the route,
#     `DistributionsController`, `DistributionPresenter` and `app/views/distributions/` are gone.
#   * "leaves the action off Home's own panels" — the negative half, pinning that the
#     `:undistributed` strip arm (deleted in Task 3) had not come back. The strip states what it
#     does and does not say in both directions in `spec/system/home/trouble_spec.rb`, so nothing
#     is lost by dropping the duplicate here.
#   * "keeps turbo from prefetching the link" — `data-turbo-prefetch="false"` on the nav item,
#     which existed only because `/distributions/new` was a GET that took write locks. There is no
#     such GET left, so the attribute has nothing to protect.
#
# ** WHY NONE OF IT SURVIVES: ** a category's money is a CLAIM computed from its rules
# (`ClaimCalculator`/`ClaimLedger`), not a balance built by handing money out. There is no paycheck
# to split, so the action that link named does not exist to be reached — the user says where the
# money goes by editing a rule on /budget. Distribute's ABSENCE is pinned below, in "replaces the
# old entries rather than adding to them", and again in `spec/system/navbar_spec.rb`'s literal
# sidebar order list.
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
    # AND THE "Distribute" ITEM IS GONE (computed-claims §§5-6): `/distributions/new` is deleted,
    # claims are computed, and a deletion nothing asserts is a link that comes back on the next
    # edit to `shared/_sidebar` with no example objecting.
    expect(page).to have_no_link("Distribute")
  end
end
