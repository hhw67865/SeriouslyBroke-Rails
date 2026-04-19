# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Show - Info Card", type: :system do
  let!(:user) { create(:user, name: "Henry Wu", email: "demo@example.com") }

  before { sign_in user, scope: :user }

  describe "account information", :aggregate_failures do
    before { visit account_path }

    it "renders the Account page with the user's name and email" do
      expect(page).to have_content("Account")
      expect(page).to have_content("Account Information")
      expect(page).to have_content("Henry Wu")
      expect(page).to have_content("demo@example.com")
      expect(page).to have_content(user.created_at.strftime("%b %d, %Y"))
    end

    it "shows an Edit action that links to the Devise edit page" do
      expect(page).to have_link("Edit", href: edit_user_registration_path)
    end
  end
end
