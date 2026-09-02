# frozen_string_literal: true

require "rails_helper"

# THE TWO DOORS AN ACCOUNT STILL HAS, ON THE SCREEN THAT NOW CARRIES THEM (two-ledger spec §5,
# Task 7). `pools/index` and `pools/show` both had a Rename and a Delete button and both screens are
# deleted; Home IS the accounts index, so the buttons are on the account's own section here.
#
# ** THE RESTORED GUARD (fix round 1, MED-1). ** `spec/system/pools/show/header_actions_spec.rb`
# carried "keeps the plain warning on an account, which has nothing above it to absorb anything" —
# the example that stopped an ENVELOPE's confirm sentence being printed over an ACCOUNT. It died
# with that file and had no successor, and the sentence it guarded against came back immediately:
# the first draft of this screen's confirm promised that "movements and any categories pointing at
# it move to your main account", which is what happens to an ENVELOPE and is false of an account
# twice over. `Pool#return_holdings_to_the_account` returns early for an account; its movements are
# DESTROYED (`dependent: :destroy`); and a category still pointing at it REFUSES the delete
# (`dependent: :restrict_with_error`). The guard is back, in both directions.
#
# The refusal itself is pinned at the wire, where the status code and the flash are visible —
# see `spec/requests/bank_accounts_spec.rb`.
RSpec.describe "Home account actions", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def account_section(name) = find("[data-account-group='#{name}']")

  describe "the buttons", :aggregate_failures do
    before { visit root_path }

    it "offers rename and delete on the account's own section" do
      within(account_section("Checking")) do
        expect(page).to have_link("Rename", href: edit_bank_account_path(checking))
        expect(page).to have_button("Delete")
      end
    end
  end

  describe "the delete confirm", :aggregate_failures do
    before { visit root_path }

    def confirm_text
      find("form[action='#{bank_account_path(checking)}']")["data-turbo-confirm"]
    end

    # THE POSITIVE HALF: it names what actually happens to the movements, and the condition on which
    # the delete does not happen at all.
    it "says the movements go and that a pointing category refuses the delete" do
      expect(confirm_text).to include("The movements into and out of it are deleted with it")
      expect(confirm_text).to include("If a category still points at it, the delete is refused")
    end

    # THE NEGATIVE HALF, and it is the one that died with `pools/show/header_actions_spec.rb`. The
    # envelope sentence must not be printed over an account: nothing of an account's moves anywhere,
    # because there is nothing above it to absorb it.
    it "never promises that anything moves to the main account" do
      expect(confirm_text).not_to include("move to your main account")
      expect(confirm_text).not_to include("returns to")
      expect(confirm_text).not_to include("buffer")
    end
  end

  describe "deleting", :aggregate_failures do
    it "removes the account's section" do
      create(:pool, :account, user: user, name: "Ally")
      visit root_path

      within(account_section("Ally")) { accept_confirm { click_button "Delete" } }

      expect(page).to have_content("Ally deleted.")
      expect(page).to have_no_css("[data-account-group='Ally']")
      expect(user.pools.count).to eq(1)
    end

    # THE REFUSAL, AT THE BROWSER: the confirm's second clause is a promise about behaviour, so the
    # behaviour is asserted rather than only the sentence. A category may point only at the user's
    # MAIN account (`Category#pool_must_be_reachable`), so main is the one account a category can
    # still be blocking.
    it "refuses while a category still points at the account, and says so" do
      create(:category, :expense, user: user, name: "Groceries", pool: checking)
      visit root_path

      within(account_section("Checking")) { accept_confirm { click_button "Delete" } }

      expect(page).to have_content("This account can't be deleted while categories still belong to it.")
      expect(page).to have_css("[data-account-group='Checking']")
      expect(user.pools.count).to eq(1)
    end
  end
end
