# frozen_string_literal: true

require "rails_helper"

# RENAMING AND DELETING A BANK ACCOUNT — the account arm of `spec/system/pools/form_spec.rb` and
# `spec/system/pools/show/header_actions_spec.rb`, which are deleted with the screens they drove
# (two-ledger spec §5, Task 7).
#
# WHAT MOVED HERE, AND WHAT DID NOT. The pool form was one screen for three kinds of pool: its
# savings and envelope halves — the target, the containing-account select, the type picker, the
# funding priority, the start date, the "also create a category" checkbox, the progress hero — all
# described shapes that no longer exist, because an envelope and a goal are CATEGORIES now. What an
# account still has is a name and a delete button, and those are the four examples below.
#
# The wire contract — the permit list, the two 404s and the destroy refusal — is pinned in
# spec/requests/bank_accounts_spec.rb, where the status codes are visible.
RSpec.describe "BankAccounts Edit", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  describe "the form", :aggregate_failures do
    before { visit edit_bank_account_path(checking) }

    # NAME ONLY, ASSERTED AS AN ABSENCE TOO. The pool form's five other controls are the whole
    # reason this screen was folded rather than kept: a "Target" box on an account is the buffer
    # marker whose last reader Task 7 deleted, and a "Funding priority" box would edit a column the
    # fill order stopped reading when it moved onto the category.
    it "offers the name and nothing else" do
      expect(page).to have_field("Account name", with: "Checking")
      expect(page).to have_no_field("Target")
      expect(page).to have_no_field("Funding priority")
      expect(page).to have_no_field("Start Date")
      expect(page).to have_no_select("Account")
    end

    it "renames the account and says so on Home" do
      fill_in "Account name", with: "Everyday Checking"
      click_button "Save account"

      expect(page).to have_content("Everyday Checking updated.")
      expect(page).to have_css("[data-account-group='Everyday Checking']")
      expect(checking.reload.name).to eq("Everyday Checking")
    end

    it "keeps the typed name beside its error when the name is refused" do
      create(:pool, :account, user: user, name: "Ally")
      fill_in "Account name", with: "ally"
      click_button "Save account"

      expect(page).to have_content("has already been taken")
      expect(page).to have_field("Account name", with: "ally")
      expect(checking.reload.name).to eq("Checking")
    end
  end

  # DELETE LIVES ON HOME, because Home is the accounts index — `pools/index` and `pools/show` both
  # carried the button and both are deleted.
  describe "deleting from Home", :aggregate_failures do
    it "removes the account's section" do
      create(:pool, :account, user: user, name: "Ally")
      visit root_path

      accept_confirm { click_button "Delete", match: :first }

      expect(page).to have_content("deleted.")
      expect(user.pools.count).to eq(1)
    end
  end
end
