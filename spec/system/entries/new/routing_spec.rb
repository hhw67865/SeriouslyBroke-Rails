# frozen_string_literal: true

require "rails_helper"

# INCOME ROUTING ON THE ENTRY FORM (main-account spec §4): "Recording income asks which account it
# lands in."
#
# THE POINT OF THE FEATURE IS THAT THE USER NEVER SEES THE MECHANISM. They pick an account; the
# entry still lands in main and a mirroring movement carries the money on. So the assertions here
# are about the two things a person can actually check — the question appearing only when it
# applies, and the money showing up in the right account on Home — rather than about the movement
# row, which `spec/requests/entries_routing_spec.rb` pins directly.
#
# Both directions on both rules: the select appears for income AND is absent for an expense; the
# chosen account gains the money AND main nets to zero rather than keeping it.
RSpec.describe "Entries New Routing", type: :system do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # ORDER IS THE FIXTURE. The first account a user is given becomes their main one, so Checking is
  # realised on the first line here and Ally after it — Ally is an account income can be routed TO
  # and never the one it lands IN. Groceries is the third pool and is not an account at all, which
  # is what makes "the select offers accounts only" a claim with something to fail against.
  before do
    salary = create(:category, :income, user: user, pool: checking, name: "Salary")
    create(:item, category: salary, name: "Paycheck")
    create(:pool, :account, user: user, name: "Ally")

    groceries = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
    food = create(:category, user: user, pool: groceries, name: "Food", category_type: :expense)
    create(:item, category: food, name: "Bananas")

    sign_in user, scope: :user
    visit new_entry_path
  end

  # The category and item pickers are TomSelects, so they are driven through their own controls
  # rather than with Capybara's `select` — the same helpers `spec/system/entries/form_spec.rb` uses.
  def select_category(name)
    find("#category_id-ts-control").click
    find("#category_id-ts-dropdown .option", text: name).click
  end

  def select_item(name)
    find("#entry_item_id-ts-control").click
    find("#entry_item_id-ts-dropdown .option", text: name).click
  end

  # A $1,000 paycheck recorded through the form, landing wherever `into` names. `into: nil` leaves
  # the select alone, which is the default the server rendered — main.
  def record_paycheck(into: nil)
    select_category("Salary")
    select_item("Paycheck")
    fill_in "Amount", with: "1000"
    select into, from: "Lands in" if into
    click_button "Create Entry"
    expect(page).to have_content("Entry was successfully created")
  end

  # $1,000 is the only money in this fixture, so every account balance on Home is either all of it or
  # none. `data-account-group` and `balance now` since Task 6: nothing is housed inside an account
  # any more, so the header carries the whole of what the bank says rather than the cash net of the
  # envelopes inside it, and the word "buffer" moved to AVAILABLE on the purpose side.
  def expect_home_buffers(checking:, ally:)
    visit root_path

    within("[data-account-group='Checking']") { expect(page).to have_content("balance now #{checking}") }
    within("[data-account-group='Ally']") { expect(page).to have_content("balance now #{ally}") }
  end

  describe "the question" do
    it "is asked for income, defaulting to the main account" do
      select_category("Salary")

      expect(page).to have_select("Lands in", selected: "Checking")
    end

    it "offers every account and nothing that is not one", :aggregate_failures do
      select_category("Salary")

      expect(page).to have_select("Lands in", options: ["Checking", "Ally"])
      expect(page).to have_no_select("Lands in", options: ["Groceries"])
    end

    it "is not asked before a category is picked" do
      expect(page).to have_no_select("Lands in")
    end

    it "is not asked for an expense" do
      select_category("Food")

      expect(page).to have_no_select("Lands in")
    end

    it "goes away again when income is swapped for an expense", :aggregate_failures do
      select_category("Salary")
      expect(page).to have_select("Lands in")

      select_category("Food")

      expect(page).to have_no_select("Lands in")
    end
  end

  describe "recording income into another account" do
    # Ally holds all of it: the entry lands in Checking and the mirror carries the same $1,000 out,
    # so Checking's buffer nets to exactly zero rather than counting the paycheck twice.
    it "puts the money in the chosen account and passes it through main" do
      record_paycheck(into: "Ally")

      expect_home_buffers(checking: "$0.00", ally: "$1,000.00")
    end

    it "leaves the money in main when main is the account chosen" do
      record_paycheck

      expect_home_buffers(checking: "$1,000.00", ally: "$0.00")
    end
  end

  describe "editing an entry that was routed" do
    it "opens on the account the money went to" do
      record_paycheck(into: "Ally")

      visit edit_entry_path(Entry.sole)

      expect(page).to have_select("Lands in", selected: "Ally")
    end

    it "moves the money when the account is changed" do
      record_paycheck(into: "Ally")

      visit edit_entry_path(Entry.sole)
      select "Checking", from: "Lands in"
      click_button "Update Entry"
      expect(page).to have_content("Entry was successfully updated")

      expect_home_buffers(checking: "$1,000.00", ally: "$0.00")
    end
  end
end
