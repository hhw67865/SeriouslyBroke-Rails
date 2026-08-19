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
end
