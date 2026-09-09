# frozen_string_literal: true

require "rails_helper"

# THE TWO DOORS AN ACCOUNT STILL HAS, ON THE SCREEN THAT NOW CARRIES THEM (two-ledger spec §5,
# Task 7). `pools/index` and `pools/show` both had a Rename and a Delete button and both screens are
# deleted; Home IS the accounts index, so the buttons are on the account's own section here.
#
# ** THE RESTORED GUARD (fix round 1, MED-1; narrowed by Task 8). ** `spec/system/pools/show/
# header_actions_spec.rb` carried "keeps the plain warning on an account, which has nothing above it
# to absorb anything" — the example that stopped an ENVELOPE's confirm sentence being printed over
# an ACCOUNT. It died with that file and had no successor, and the sentence it guarded against came
# back immediately: the first draft of this screen's confirm promised that "movements and any
# categories pointing at it move to your main account", which is what happens to an ENVELOPE and was
# false of an account twice over.
#
# ONE OF THOSE TWO HALVES IS NOW MOOT. No category points at an account (`categories.pool_id` is
# dropped, two-ledger spec §5), so the refusal the confirm used to promise cannot be raised by
# anything and its example is deleted with it. What is left is the half that was always the
# account's own: `dependent: :destroy` DELETES its movements, so the money they moved goes back to
# the pot rather than being absorbed by something above it — because there is nothing above it.
#
# ** MAIN HAS NO DELETE BUTTON (final fix wave, C-1), which is why every example below that is about
# deleting is about ALLY. ** `checking` is this file's main account (the pool factory makes the first
# account the user's default, exactly as `BankAccountsController#create` does), and main is on one
# side of every AccountMovement the app writes — so `dependent: :destroy` over its movements took the
# whole physical ledger and zeroed `pot + Σ accounts` against an untouched purpose ledger. The model
# refuses it and this screen does not offer it; the crafted DELETE is pinned in
# `spec/requests/bank_accounts_spec.rb`, where the status and the flash are visible.
RSpec.describe "Home account actions", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, :opened, user: user, name: "Checking") }
  let!(:ally) { create(:pool, :account, :opened, user: user, name: "Ally") }

  before { sign_in user, scope: :user }

  def account_section(name) = find("[data-account-group='#{name}']")

  # ** THE CARDS LIVE BEHIND THE ACCOUNTS LINE, AND `:opened` IS WHAT PUTS THEM THERE
  # (account-openings spec §3). ** An account that has not said what it holds has a ROW in the "Your
  # accounts" card and no card of its own — no Rename, no Delete — so every example in this file is
  # about an account that has answered. Before this task both fixtures were mid-onboarding and their
  # cards rendered top-level; the two doors this file is about were reachable by accident.
  def open_the_line
    visit root_path
    find("[data-accounts-line]").click
  end

  describe "the buttons", :aggregate_failures do
    before { open_the_line }

    it "offers rename and delete on an ordinary account's own section" do
      within(account_section("Ally")) do
        expect(page).to have_link("Rename", href: edit_bank_account_path(ally))
        expect(page).to have_button("Delete")
      end
    end

    # BOTH DIRECTIONS ON ONE SCREEN. Main keeps its Rename — a typo in a bank name is still a typo —
    # and loses only the door the model refuses, so the absence reads as a rule about main rather
    # than as a missing feature.
    it "offers rename but no delete on the main account, and says why" do
      within(account_section("Checking")) do
        expect(page).to have_link("Rename", href: edit_bank_account_path(checking))
        expect(page).to have_no_button("Delete")
        expect(page).to have_content("Main account — everything flows through it")
      end
    end

    it "says nothing about the main role on an account that does not have it" do
      within(account_section("Ally")) do
        expect(page).to have_no_content("Main account")
      end
    end
  end

  describe "the delete confirm", :aggregate_failures do
    before { open_the_line }

    def confirm_text
      find("form[action='#{bank_account_path(ally)}']")["data-turbo-confirm"]
    end

    # THE POSITIVE HALF: it names what actually happens to the movements, and where the money they
    # moved ends up.
    #
    # ** "GOES BACK TO YOUR MAIN ACCOUNT" IS TRUE, RE-VERIFIED (final fix wave, C-1). ** Both writers
    # of an AccountMovement — `Entry#route_income_to!` and `AccountOpening#write_movement`
    # — put `user.default_account` on `from_pool`, so main is on the OTHER side of every movement a
    # deletable account has: destroying them restores main's `moves out` and the pot rises by exactly
    # what the account held. The ledger half of that claim is asserted in the request spec; here it is
    # only the sentence. The confirm is now rendered on non-main accounts alone, which is precisely
    # the population it is true of.
    it "says the movements go and the money they moved comes back" do
      expect(confirm_text).to include("The movements into and out of it are deleted with it")
      expect(confirm_text).to include("the money they moved goes back to your main account")
    end

    # THE NEGATIVE HALF, and it is the one that died with `pools/show/header_actions_spec.rb`. The
    # envelope sentence must not be printed over an account: the account's MOVEMENTS do not move
    # anywhere, they are deleted, and there is nothing above it to absorb them. The distinction the
    # strings below draw is between the money coming BACK because a transfer was undone (true, and
    # asserted above) and the movements themselves being re-pointed (the envelope's, and false).
    it "never promises that the movements themselves move to the main account" do
      expect(confirm_text).not_to include("movements and any categories")
      expect(confirm_text).not_to include("move to your main account")
      expect(confirm_text).not_to include("returns to")
      expect(confirm_text).not_to include("buffer")
    end
  end

  describe "deleting", :aggregate_failures do
    it "removes the account's section" do
      open_the_line

      within(account_section("Ally")) { accept_confirm { click_button "Delete" } }

      expect(page).to have_content("Ally deleted.")
      expect(page).to have_no_css("[data-account-group='Ally']")
      expect(user.pools.count).to eq(1)
    end

    # THE OTHER DIRECTION, ON THE SCREEN. Deleting the only deletable account leaves main standing
    # with its section, its Rename and no Delete — so a user cannot reach the empty-of-accounts state
    # the C-1 regression produced by clicking twice.
    it "leaves the main account on the page with no way to delete it" do
      open_the_line
      within(account_section("Ally")) { accept_confirm { click_button "Delete" } }
      expect(page).to have_content("Ally deleted.")

      find("[data-accounts-line]").click
      within(account_section("Checking")) do
        expect(page).to have_link("Rename")
        expect(page).to have_no_button("Delete")
      end
      expect(user.reload.default_account).to eq(checking)
    end

    # ── "refuses while a category still points at the account" IS DELETED WITH THE REFUSAL
    # (two-ledger spec §5, Task 8). `has_many :categories, dependent: :restrict_with_error` is gone
    # with `categories.pool_id`: nothing points at an account, so nothing can block its delete and
    # the confirm no longer promises that it might.
  end
end
