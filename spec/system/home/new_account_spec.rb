# frozen_string_literal: true

require "rails_helper"

# The user-visible faces of the "+ Add an account" row at the foot of Home's "Your accounts" card.
# The wire contract — which params the controller accepts, the 422, and the balance arm's own
# rollback — is pinned in spec/requests/bank_accounts_spec.rb; what the row DOES with a balance is
# spec/system/home/openings_spec.rb's subject, because it is the same act every other row on that
# card performs.
#
# ── DELETED WITH ONBOARDING STEP 2 (account-openings spec §3), successor named: the "funding a fresh
# account" pair ("moves the entered balance from main, then the card is gone" and "shows the card
# only on a non-main account's section"). Adding an account and saying what is in it is ONE row now,
# and the second example's rule — main gets no card because it has no real balance of its own — is
# reversed outright: main is asked what it holds exactly like every other account.
# `spec/system/home/openings_spec.rb` is where both live on.
RSpec.describe "Home NewAccount", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, :opened, user: user, name: "Checking") }

  before do
    sign_in user, scope: :user
    visit root_path
  end

  def add_account(name)
    within("form[action='#{bank_accounts_path}']") do
      fill_in "Account name", with: name
      click_button "Add an account"
    end
  end

  describe "creating a bank account", :aggregate_failures do
    # A NAME ALONE IS STILL ENOUGH. The balance beside it is optional — "I don't know yet" is a real
    # answer — and an account added without one keeps a row in the card until the user says.
    it "creates an account pool and asks what is in it" do
      add_account("Ally Savings")

      expect(page).to have_content("Ally Savings added.")
      expect(page).to have_css("[data-account-row='Ally Savings']")
      expect(user.pools.find_by(name: "Ally Savings")).to be_pool_type_account
      expect(user.pools.find_by(name: "Ally Savings").opened_on).to be_nil
    end

    it "keeps the typed name beside its error when the name is refused" do
      add_account(checking.name.downcase)

      expect(page).to have_content("has already been taken")
      expect(page).to have_field("Account name", with: checking.name.downcase)
      expect(user.pools.count).to eq(1)
    end
  end
end
