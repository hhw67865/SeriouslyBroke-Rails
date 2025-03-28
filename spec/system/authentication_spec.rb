# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication", type: :system do
  describe "Sign up" do
    before { visit new_user_registration_path }

    describe "page content", :aggregate_failures do
      it "shows all required elements" do
        expect(page).to have_content("Create your account")
        expect(page).to have_content("Start managing your finances today")
        expect(page).to have_link("Back to Home")
        expect(page).to have_link("Already have an account? Sign in")
      end
    end

    context "with valid information" do
      let(:valid_email) { "test@example.com" }
      let(:valid_password) { "password123" }

      it "allows form submission with valid email" do
        fill_sign_up_form
        expect(page).not_to have_css("input:invalid")
      end

      it "completes sign up successfully", :aggregate_failures do
        fill_sign_up_form
        within("form") { click_button "Sign up" }

        expect(page).to have_content("Welcome! You have signed up successfully.")
        expect(page).to have_current_path(authenticated_root_path)
      end

      private

      def fill_sign_up_form(email: valid_email, password: valid_password, confirmation: nil)
        within("form") do
          fill_in "Email", with: email
          fill_in "Password", with: password
          fill_in "Password confirmation", with: confirmation || password
        end
      end
    end

    context "with invalid information" do
      it "prevents submission with invalid email format" do
        fill_in "Email", with: "invalid-email"
        fill_in "Password", with: "password123"
        fill_in "Password confirmation", with: "password123"
        expect(page).to have_css("input[type=email]:invalid")
      end

      it "shows error for short password" do
        fill_in "Email", with: "test@example.com"
        fill_in "Password", with: "123"
        fill_in "Password confirmation", with: "123"
        click_button "Sign up"

        expect(page).to have_content("Password is too short")
      end

      it "shows error for mismatched password confirmation" do
        fill_in "Email", with: "test@example.com"
        fill_in "Password", with: "password123"
        fill_in "Password confirmation", with: "different123"
        click_button "Sign up"

        expect(page).to have_content("Password confirmation doesn't match")
      end
    end

    context "with duplicate email" do
      before { create(:user, email: "test@example.com") }

      it "shows error message" do
        submit_duplicate_email
        expect(page).to have_content("Email has already been taken")
      end

      private

      def submit_duplicate_email
        fill_in "Email", with: "test@example.com"
        fill_in "Password", with: "password123"
        fill_in "Password confirmation", with: "password123"
        click_button "Sign up"
      end
    end

    describe "navigation", :aggregate_failures do
      it "provides correct navigation links" do
        click_link "Already have an account? Sign in"
        expect(page).to have_content("Welcome back")

        visit new_user_registration_path
        click_link "Back to Home"
        expect(page).to have_current_path(root_path)
      end
    end
  end

  describe "Sign in" do
    let!(:user) { create(:user, email: "test@example.com", password: "password123") }

    before { visit new_user_session_path }

    describe "page content", :aggregate_failures do
      it "shows all required elements" do
        expect(page).to have_content("Welcome back")
        expect(page).to have_content("Sign in to manage your finances")
        expect(page).to have_link("Back to Home")
        expect(page).to have_link("Don't have an account? Sign up")
      end
    end

    context "with valid credentials" do
      it "signs in successfully", :aggregate_failures do
        sign_in_with_credentials

        expect(page).to have_content("Signed in successfully")
        expect(page).to have_current_path(authenticated_root_path)
      end

      it "remembers the user when requested", :aggregate_failures do
        sign_in_with_credentials(remember_me: true)

        expect(page).to have_content("Signed in successfully")
        expect(page).to have_current_path(authenticated_root_path)
      end

      private

      def sign_in_with_credentials(remember_me: false)
        within("form") do
          fill_in "Email", with: user.email
          fill_in "Password", with: "password123"
          check "Remember me" if remember_me
          click_button "Sign in"
        end
      end
    end

    context "with invalid credentials" do
      it "shows error for wrong password" do
        attempt_sign_in(user.email, "wrongpassword")
        expect(page).to have_content("Invalid Email or password")
      end

      it "shows error for non-existent email" do
        attempt_sign_in("nonexistent@example.com", "password123")
        expect(page).to have_content("Invalid Email or password")
      end

      it "shows error for empty credentials" do
        within("form") { click_button "Sign in" }
        expect(page).to have_content("Invalid Email or password")
      end

      private

      def attempt_sign_in(email, password)
        within("form") do
          fill_in "Email", with: email
          fill_in "Password", with: password
          click_button "Sign in"
        end
      end
    end

    describe "navigation", :aggregate_failures do
      it "provides correct navigation links" do
        click_link "Don't have an account? Sign up"
        expect(page).to have_content("Create your account")

        visit new_user_session_path
        click_link "Back to Home"
        expect(page).to have_current_path(root_path)
      end
    end
  end

  describe "Sign out" do
    let!(:user) { create(:user, email: "test@example.com", password: "password123") }

    before do
      sign_in user
      visit authenticated_root_path
    end

    it "signs out successfully", :aggregate_failures do
      click_on "Sign out"

      expect(page).to have_content("Signed out successfully")
      expect(page).to have_current_path(root_path)
      expect(page).not_to have_content(user.name || user.email)
    end
  end
end
