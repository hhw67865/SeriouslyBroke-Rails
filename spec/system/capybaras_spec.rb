# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Capybaras Overlay", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
  end

  describe "ming mode on" do
    it "renders the capybara layer" do
      user.update!(ming_mode: true)
      visit account_path

      expect(page).to have_css("#capybara-layer", visible: :all)
    end
  end

  describe "ming mode off" do
    it "does not render the capybara layer" do
      visit account_path

      expect(page).to have_no_css("#capybara-layer", visible: :all)
    end
  end
end
