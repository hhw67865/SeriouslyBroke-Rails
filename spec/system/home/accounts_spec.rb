# frozen_string_literal: true

require "rails_helper"

# HOME'S ACCOUNTS: one line that says how much of the user's money is somewhere other than checking,
# and an expansion that is the accounts index — Home carries rename and delete, so every account's
# card stays reachable, main's included. The add-account door stays outside the line.
RSpec.describe "Home accounts", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }

  before { sign_in user, scope: :user }

  def elsewhere(name, balance) = create(:account, user: user, name: name, opening_balance: balance)

  def read_home = travel_to(today) { visit root_path }

  def line = find("[data-accounts-line]")

  def account_card(name) = find("[data-account-group='#{name}']")

  def add_account(name, balance: nil)
    within("form[action='#{accounts_path}']") do
      fill_in "Account name", with: name
      fill_in "What's in it right now", with: balance if balance
      click_button "Add an account"
    end
  end

  # ── THE LINE ───────────────────────────────────────────────────────────────────────────────────

  # Both halves are asserted, because a line that summed the wrong set would still print a plausible
  # total. Main is not in the figure: its balance is the money row's own "In checking".
  it "collapses the other accounts to one line with their total", :aggregate_failures do
    elsewhere("Ally", 222_000)
    elsewhere("Vanguard", 544.87)

    read_home

    expect(line).to have_content("$222,544.87 across 2 other accounts")
    expect(line).to have_no_content("$1,000.00")
  end

  # The singular, because "1 other accounts" is the kind of thing a reader stops trusting a screen
  # over — and the other direction, where a figure would be an invented absence.
  it "counts one account in the singular and names a lone account plainly", :aggregate_failures do
    elsewhere("Ally", 400)

    read_home

    expect(line).to have_content("$400.00 across 1 other account")

    Account.find_by(name: "Ally").destroy!
    read_home

    expect(line).to have_content("Account details")
    expect(line).to have_no_content("other account")
  end

  # The cards are collapsed, not absent — and "collapsed" is Capybara's own visibility rule, which
  # is what `<details>` gives for free.
  it "hides the account cards until the line is opened", :aggregate_failures do
    elsewhere("Ally", 400)

    read_home

    expect(page).to have_no_css("[data-account-group='Ally']")
    expect(page).to have_css("[data-account-group='Ally']", visible: :hidden)
  end

  it "opens to today's account cards and their two doors", :aggregate_failures do
    ally = elsewhere("Ally", 400)

    read_home
    line.click

    expect(account_card("Ally")).to have_content("balance now $400.00")
    expect(account_card("Ally")).to have_link("Rename", href: edit_account_path(ally))
    expect(account_card("Ally")).to have_button("Delete")
  end

  # Main is in the expansion even though it is not in the line's figure, and it keeps its Rename and
  # loses only the door the model refuses — so the absence reads as a rule about main rather than as
  # a missing feature.
  it "keeps the main account reachable and undeletable", :aggregate_failures do
    elsewhere("Ally", 400)

    read_home
    line.click

    expect(account_card("Checking")).to have_content("Main account — everything flows through it")
    expect(account_card("Checking")).to have_link("Rename", href: edit_account_path(checking))
    expect(account_card("Checking")).to have_no_button("Delete")
    expect(account_card("Ally")).to have_no_content("Main account")
  end

  # An overdrawn account's own number, red, inside the expansion.
  it "prints an overdrawn account's balance as the debt it is", :aggregate_failures do
    ally = elsewhere("Ally", 0)
    create(:transfer, from_account: ally, to_account: checking, amount: 40, date: today)

    read_home
    line.click

    expect(account_card("Ally")).to have_css(".text-status-danger", text: "-$40.00")
  end

  # ── THE THREE DOORS ────────────────────────────────────────────────────────────────────────────

  # Adding an account asks both things at once, because for the user they are one act: a name and
  # what is in it. The add form is top-level — a door behind a chevron is a door a first-time user
  # does not find.
  it "adds an account with a balance", :aggregate_failures do
    read_home
    add_account("Ally Savings", balance: "250.50")

    expect(page).to have_content("Ally Savings added.")
    expect(line).to have_content("$250.50 across 1 other account")

    line.click

    expect(account_card("Ally Savings")).to have_content("balance now $250.50")
  end

  # A user with no accounts at all still gets the door, and the figures read zero rather than
  # reaching for a balance no account has.
  describe "a user with nothing yet" do
    let(:newcomer) { create(:user, :biweekly) }

    before { sign_in newcomer, scope: :user }

    it "is asked for their first account", :aggregate_failures do
      read_home

      expect(page).to have_field("Account name")
      expect(page).to have_css("[data-in-checking]", text: "$0.00")
      expect(page).to have_no_css("[data-accounts]")
    end
  end

  it "keeps the typed name beside its error when the name is refused", :aggregate_failures do
    read_home
    add_account("checking")

    expect(page).to have_content("has already been taken")
    expect(page).to have_field("Account name", with: "checking")
    expect(user.accounts.count).to eq(1)
  end

  it "renames an account and corrects what it holds", :aggregate_failures do
    elsewhere("Ally", 400)

    read_home
    line.click
    within(account_card("Ally")) { click_link "Rename" }

    fill_in "Account name", with: "Ally Savings"
    fill_in "Balance today", with: "525.25"
    click_button "Save account"

    expect(page).to have_content("Ally Savings updated.")

    line.click

    expect(account_card("Ally Savings")).to have_content("balance now $525.25")
  end

  it "refuses a balance that is not a number", :aggregate_failures do
    elsewhere("Ally", 400)

    read_home
    line.click
    within(account_card("Ally")) { click_link "Rename" }

    fill_in "Balance today", with: "quite a lot"
    click_button "Save account"

    expect(page).to have_content("is not a number")
    expect(Account.find_by(name: "Ally").balance).to eq(400)
  end

  # Deleting takes the account's transfers with it, and main is on the other end of every one — so
  # the money they moved goes back to checking and the flash says how much.
  it "deletes an account and says what came back", :aggregate_failures do
    ally = elsewhere("Ally", 0)
    create(:transfer, from_account: checking, to_account: ally, amount: 300, date: today)

    read_home
    line.click
    within(account_card("Ally")) { click_button "Delete" }

    expect(page).to have_content("Ally deleted — $300.00 is back in checking.")
    expect(page).to have_no_css("[data-account-group='Ally']", visible: :all)
    expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
  end

  # What the confirm promises, checked against what deleting actually does: the transfers are
  # deleted rather than re-pointed, and the money they moved is what comes back.
  it "says what deleting will do before it does it", :aggregate_failures do
    ally = elsewhere("Ally", 400)

    read_home
    line.click
    confirm = find("form[action='#{account_path(ally)}']")["data-turbo-confirm"]

    expect(confirm).to include("The transfers into and out of it are deleted with it")
    expect(confirm).to include("the money they moved goes back to your main account")
    expect(confirm).not_to include("categories")
  end
end
