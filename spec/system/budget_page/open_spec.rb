# frozen_string_literal: true

require "rails_helper"

# Opening a category. The mechanism is a link — every chevron carries `?open=<id>`, or bare
# `/budget` on the open row — so the page works with scripting off; every closed panel is
# nonetheless rendered and `hidden`, which is what lets category_list_controller flip them in place
# without a round trip, and what makes Capybara's default visibility filter the right test for "is
# this open".
RSpec.describe "Budget page open category", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
    rule_on("Groceries", amount: 400, priority: 0)
    rule_on("Rent", amount: 900, priority: 1)
  end

  def rule_on(name, amount:, priority: 0)
    create(
      :rule,
      :rate,
      amount: amount,
      starts_on: Date.new(2026, 1, 1),
      category: create(:category, user: user, name: name, priority: priority)
    )
  end

  def category(name) = user.categories.find_by!(name: name)
  def chevron(name) = find("[data-category-row='#{name}']").find("[data-category-toggle]")
  def open_panels = page.all("[data-category-panel]").pluck("data-category-panel")

  describe "the `open` parameter, which is the whole no-JavaScript mechanism", :aggregate_failures do
    it "opens exactly the category it names, and nothing without it" do
      visit budget_page_path
      expect(open_panels).to be_empty

      visit budget_page_path(open: category("Groceries").id)

      expect(open_panels).to eq(["Groceries"])
    end

    # Asserted on the `href` rather than by clicking, because a click goes through the Stimulus
    # controller — the next group's subject — and this is about what the server rendered.
    it "carries the parameter on the chevron, and drops it on the open one" do
      visit budget_page_path(open: category("Groceries").id)

      expect(chevron("Rent")[:href]).to include("open=#{category("Rent").id}")
      expect(URI.parse(chevron("Groceries")[:href]).query).to be_nil
    end

    # The page never looks the parameter up — it compares it against the ids it rendered — so a
    # stranger's category is a page with nothing open rather than a 404 or a leak.
    it "opens nothing for an id that is not this user's" do
      stranger = create(:category, user: create(:user), name: "Theirs")

      visit budget_page_path(open: stranger.id)

      expect(open_panels).to be_empty
      expect(page).to have_no_content("Theirs")
    end
  end

  describe "one at a time, flipped in place", :aggregate_failures, :js do
    before { visit budget_page_path }

    # The URL is asserted UNCHANGED, which is what says there was no round trip: the controller
    # intercepts the link and moves the `hidden` attribute from one panel to the other.
    it "opens one and closes the last without leaving the page" do
      chevron("Groceries").click
      expect(page).to have_css("[data-category-panel='Groceries']")

      chevron("Rent").click

      expect(page).to have_css("[data-category-panel='Rent']")
      expect(open_panels).to eq(["Rent"])
      expect(page).to have_current_path(budget_page_path)
    end

    # Clicking the open one closes it — the same control saying both halves of one state, which is
    # why the chevron is one link and not two.
    it "closes the open one when its own chevron is clicked" do
      chevron("Groceries").click
      expect(page).to have_css("[data-category-panel='Groceries']")

      chevron("Groceries").click

      expect(page).to have_no_css("[data-category-panel='Groceries']")
    end
  end
end
