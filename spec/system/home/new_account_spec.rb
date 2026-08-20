# frozen_string_literal: true

require "rails_helper"

# The two user-visible faces of the Home add-account card. The wire contract — which params
# the controller accepts and the 422 — is pinned in spec/requests/bank_accounts_spec.rb.
RSpec.describe "Home NewAccount", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before do
    sign_in user, scope: :user
    visit root_path
  end

  def add_account(name)
    within("form[action='#{bank_accounts_path}']") do
      fill_in "Account name", with: name
      click_button "Add account"
    end
  end

  def fund_account(section, amount)
    within(section) do
      fill_in "Real balance today", with: amount
      click_button "Fund account"
    end
  end

  describe "creating a bank account", :aggregate_failures do
    it "creates an account pool and renders its section on Home" do
      add_account("Ally Savings")

      expect(page).to have_content("Ally Savings added.")
      expect(page).to have_css("[data-pool-group='Ally Savings']")
      expect(user.pools.find_by(name: "Ally Savings")).to be_pool_type_account
    end

    it "keeps the typed name beside its error when the name is refused" do
      add_account(checking.name.downcase)

      expect(page).to have_content("has already been taken")
      expect(page).to have_field("Account name", with: checking.name.downcase)
      expect(user.pools.count).to eq(1)
    end
  end

  # ONBOARDING STEP 2 (main-account spec §5): the fund-account card, chained onto step 1's own
  # card — create the account here, then give it the ONE movement from main that mirrors its
  # real balance. The wire contract (the 422s) is pinned in spec/requests/account_fundings_spec.rb.
  describe "funding a fresh account", :aggregate_failures do
    it "moves the entered balance from main, then the card is gone" do
      add_account("Ally Savings")
      section = "[data-pool-group='Ally Savings']"
      expect(page).to have_css(section)

      fund_account(section, "1200.50")

      expect(page).to have_content("Ally Savings funded with $1,200.50.")
      within(section) do
        expect(page).to have_content("buffer now $1,200.50")
        expect(page).not_to have_field("Real balance today")
      end
    end

    it "keeps the typed amount beside its error when the amount is refused" do
      add_account("Ally Savings")
      section = "[data-pool-group='Ally Savings']"

      fund_account(section, "0")

      expect(page).to have_content("must be greater than 0")
      within(section) { expect(page).to have_field("Real balance today", with: "0") }
      expect(PoolMovement.count).to eq(0)
    end
  end
end
