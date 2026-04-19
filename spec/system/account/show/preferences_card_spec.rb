# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Show - Preferences Card", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit account_path
  end

  describe "theme toggle", :aggregate_failures do
    it "starts on light and flips to dark when clicked" do
      expect(user.theme).to eq("light")
      expect(page).to have_content("Theme")

      find("dt", text: "Theme").ancestor(".py-3").find("button").click

      expect(user.reload.theme).to eq("dark")
    end

    it "flips dark back to light when clicked" do
      user.update!(theme: :dark)
      visit account_path

      find("dt", text: "Theme").ancestor(".py-3").find("button").click

      expect(user.reload.theme).to eq("light")
    end
  end

  describe "ming mode toggle", :aggregate_failures do
    it "starts off and flips on when clicked" do
      expect(user.ming_mode).to be false
      expect(page).to have_content("Ming Mode")

      find("dt", text: "Ming Mode").ancestor(".py-3").find("button").click

      expect(user.reload.ming_mode).to be true
    end

    it "flips on back to off when clicked" do
      user.update!(ming_mode: true)
      visit account_path

      find("dt", text: "Ming Mode").ancestor(".py-3").find("button").click

      expect(user.reload.ming_mode).to be false
    end
  end
end
