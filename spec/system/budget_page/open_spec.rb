# frozen_string_literal: true

require "rails_helper"

# ** OPENING A CATEGORY (two-shapes spec §4). ** Henry, 2026-09-05: "Expanded should just show all
# rules and suggestions. The new rule thing should be a form we go to." So the open panel is three
# things, in that order — the rules table, what the entries suggest for THIS category, and one
# button to write another rule — and one category is open at a time.
#
# ** THE MECHANISM IS A LINK, AND THE JAVASCRIPT IS THE ENHANCEMENT. ** Every chevron carries
# `?open=<id>` (or bare `/budget` on the open row), so the page works with scripting off; every
# closed panel is nonetheless RENDERED and `hidden`, which is what lets
# `category_list_controller.js` flip them in place without a round trip and what makes Capybara's
# default visibility filter the right test for "is this open".
RSpec.describe "Budget page open category", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end

  before { sign_in user, scope: :user }

  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  def row(name) = find("[data-category-row='#{name}']")

  def chevron(name) = row(name).find("[data-category-toggle]")

  def open_panels = page.all("[data-category-panel]", visible: true).pluck("data-category-panel")

  describe "the `open` parameter, which is the whole no-JavaScript mechanism", :aggregate_failures do
    before do
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Rent", priority: 2), 900)
    end

    it "opens exactly the category it names, and nothing without it" do
      visit budget_page_path

      expect(open_panels).to be_empty

      visit budget_page_path(open: user.categories.find_by!(name: "Groceries").id)

      expect(open_panels).to eq(["Groceries"])
    end

    # ** THE CHEVRON IS A LINK CARRYING THAT PARAMETER, so the page is reachable without scripting
    # at all. ** Asserted on the `href` rather than by clicking, because a click here goes through
    # the Stimulus controller — which is the next group's subject — and this is about what the
    # server rendered.
    it "carries the parameter on the chevron, and drops it on the open one" do
      visit budget_page_path(open: user.categories.find_by!(name: "Groceries").id)

      expect(chevron("Rent")[:href]).to include("open=#{user.categories.find_by!(name: "Rent").id}")
      expect(URI.parse(chevron("Groceries")[:href]).query).to be_nil
    end

    # AN ID THAT IS NOT THIS USER'S MATCHES NO ROW. The page never looks the parameter up — it
    # compares it against the ids it rendered — so a stranger's category is a page with nothing
    # open rather than a 404 or a leak.
    it "opens nothing for an id that is not this user's" do
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Theirs")

      visit budget_page_path(open: stranger.id)

      expect(open_panels).to be_empty
      expect(page).to have_no_content("Theirs")
    end
  end

  describe "one at a time, and remembered", :aggregate_failures do
    before do
      rate(holder("Groceries", priority: 1), 400)
      rate(holder("Rent", priority: 2), 900)
      visit budget_page_path
    end

    # ** THE FLIP IS IN PLACE AND CLOSES THE OTHER ONE (§4). ** The URL is asserted UNCHANGED, which
    # is what says there was no round trip: the controller intercepts the link and moves the
    # `hidden` attribute from one panel to the other.
    it "opens one and closes the last without leaving the page" do
      chevron("Groceries").click
      expect(page).to have_css("[data-category-panel='Groceries']")

      chevron("Rent").click

      expect(open_panels).to eq(["Rent"])
      expect(page).to have_current_path(budget_page_path)
    end

    # CLICKING THE OPEN ONE CLOSES IT — the same control saying both halves of one state, which is
    # why the chevron is one link and not two.
    it "closes the open one when its own chevron is clicked" do
      chevron("Groceries").click
      expect(page).to have_css("[data-category-panel='Groceries']")

      chevron("Groceries").click

      expect(open_panels).to be_empty
    end

    # ** REMEMBERED PER VIEWER, IN localStorage (§4). ** The memory is the browser's, not the
    # server's: a bare `/budget` opens nothing server-side (pinned above), so a panel open after a
    # plain reload can only have come from the store.
    it "reopens the last one on a plain reload" do
      chevron("Rent").click
      expect(page).to have_css("[data-category-panel='Rent']")

      visit budget_page_path

      expect(page).to have_css("[data-category-panel='Rent']")
      expect(open_panels).to eq(["Rent"])
    end

    # ** AND THE SERVER-RENDERED ONE WINS. ** A page that arrived with `?open=` is showing the
    # category the user just asked for — a link, a redirect after an adjustment, the categories
    # page's pointer — and restoring the store over it would be the browser overruling the URL.
    it "lets a named category beat the remembered one" do
      chevron("Rent").click
      expect(page).to have_css("[data-category-panel='Rent']")

      visit budget_page_path(open: user.categories.find_by!(name: "Groceries").id)

      expect(open_panels).to eq(["Groceries"])
    end
  end

  describe "what the open category shows", :aggregate_failures do
    let(:groceries) { holder("Groceries", priority: 1) }
    let(:utilities) { holder("Utilities", priority: 2) }

    before do
      rate(groceries, 400)
      rate(utilities, 120)
    end

    # THE RULES TABLE, AND ONLY THIS CATEGORY'S RULES.
    it "shows this category's rules and not another's" do
      visit budget_page_path(open: groceries.id)

      within("[data-category-panel='Groceries']") do
        expect(page).to have_css("[data-rule='Groceries']")
        expect(page).to have_no_css("[data-rule='Utilities']")
      end
    end

    # ** ONLY THIS CATEGORY'S SUGGESTIONS (§4), which is the partition said on screen. ** Both
    # directions on one render: the proposal about the open category is there and the one about its
    # neighbour is not — a panel rendering the engine's whole list would pass a presence check alone.
    it "shows only this category's suggestions" do
      coffee = create(:category, :expense, user: user, name: "Coffee")
      beans = create(:item, category: coffee, name: "Beans")
      [42, 28, 14].each { |back| create(:entry, item: beans, amount: 150, date: Date.current - back.days) }
      tea = create(:item, category: create(:category, :expense, user: user, name: "Tea"), name: "Leaves")
      [42, 28, 14].each { |back| create(:entry, item: tea, amount: 90, date: Date.current - back.days) }

      visit budget_page_path(open: coffee.id)

      within("[data-suggestions='Coffee']") do
        expect(page).to have_content("Coffee — $150.00 a period")
        expect(page).to have_no_content("Tea")
      end
    end

    # ** ONE BUTTON, AND THE FORM IS ITS OWN PAGE (§4/§5). ** It carries the category, so the form
    # opens knowing what the rule is for and the user never picks an owner out of a select — which
    # is the same door the suggestion rows' "Write it →" goes through.
    it "offers one new-rule button that carries the category" do
      visit budget_page_path(open: groceries.id)

      within("[data-category-panel='Groceries']") { click_link "+ New rule for Groceries" }

      expect(page).to have_current_path(new_budget_path(category_id: groceries.id))
      expect(page).to have_content("Groceries")
      expect(page).to have_no_select("Category")
    end

    # ** NOTHING ELSE IS ON THE PAGE (§4/§7). ** The five panels that died are asserted absent BY
    # THEIR OWN HOOKS: a regression restoring any of them would put the same facts on the screen
    # twice, in two places that are free to disagree.
    it "says the retired panels' facts once, in the tiles and the rows" do
      visit budget_page_path(open: groceries.id)

      expect(page).to have_no_css("[data-type-overview]")
      expect(page).to have_no_css("[data-structural-check]")
      expect(page).to have_no_css("[data-fill-order]")
      expect(page).to have_no_css("[data-not-filling]")
      expect(page).to have_no_css("[data-suggestions-index]")
      expect(page).to have_css("[data-tiles]")
    end
  end
end
