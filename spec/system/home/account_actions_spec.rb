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

    # THE POSITIVE HALF: it names what actually happens to the movements, and where the money they
    # moved ends up.
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
      create(:pool, :account, user: user, name: "Ally")
      visit root_path

      within(account_section("Ally")) { accept_confirm { click_button "Delete" } }

      expect(page).to have_content("Ally deleted.")
      expect(page).to have_no_css("[data-account-group='Ally']")
      expect(user.pools.count).to eq(1)
    end

    # ── "refuses while a category still points at the account" IS DELETED WITH THE REFUSAL
    # (two-ledger spec §5, Task 8). `has_many :categories, dependent: :restrict_with_error` is gone
    # with `categories.pool_id`: nothing points at an account, so nothing can block its delete and
    # the confirm no longer promises that it might.
  end
end
