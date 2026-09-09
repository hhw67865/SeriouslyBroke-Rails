# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Show - Preferences Card", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit account_path
  end

  # EVERY EXAMPLE HERE WAITS ON THE BROWSER BEFORE IT READS THE MODEL, and that is the fix for the
  # `InvalidSessionIdError` all four of them raised (with zero assertion failures) at every commit
  # since this file arrived. `click` returns as soon as the click is dispatched, while
  # `expect(user.reload…)` reads Postgres without waiting on anything — so the example ended
  # mid-request and Capybara's `reset_sessions!` navigated the renderer away underneath it. See
  # CLAUDE.md → *Diagnosing `InvalidSessionIdError`*; this is the fourth file with the same defect.
  #
  # The wait is on the TRACK's colour rather than on the thumb's position, and the difference is
  # the whole point: the Stimulus controller flips the thumb optimistically on click, so the thumb
  # is already in place before the request is sent and waiting on it would wait for nothing. Only
  # the track (`bg-brand` / `bg-gray-300`) is rendered from `current_user`, so it cannot change
  # until the PATCH has been handled and the redirect re-rendered — which is exactly the moment
  # the model assertion below it becomes safe to make.
  #
  # Scoped by the form's action rather than by a row element, because the row this was found in is
  # gone by then: the toggle redirects, so any node captured before the click is stale after it.
  def toggle(row)
    find("dt", text: row).ancestor(".py-3").find("button").click
  end

  def track_for(path) = "form[action='#{path}'] button"

  describe "theme toggle", :aggregate_failures do
    it "starts on light and flips to dark when clicked" do
      expect(user.theme).to eq("light")
      expect(page).to have_content("Theme")

      toggle("Theme")

      expect(page).to have_css("#{track_for(toggle_theme_account_path)}.bg-brand-dark")
      expect(user.reload.theme).to eq("dark")
    end

    it "flips dark back to light when clicked" do
      user.update!(theme: :dark)
      visit account_path

      toggle("Theme")

      expect(page).to have_css("#{track_for(toggle_theme_account_path)}.bg-gray-300")
      expect(user.reload.theme).to eq("light")
    end
  end

  describe "ming mode toggle", :aggregate_failures do
    it "starts off and flips on when clicked" do
      expect(user.ming_mode).to be false
      expect(page).to have_content("Ming Mode")

      toggle("Ming Mode")

      expect(page).to have_css("#{track_for(toggle_ming_mode_account_path)}.bg-brand-dark")
      expect(user.reload.ming_mode).to be true
    end

    it "flips on back to off when clicked" do
      user.update!(ming_mode: true)
      visit account_path

      toggle("Ming Mode")

      expect(page).to have_css("#{track_for(toggle_ming_mode_account_path)}.bg-gray-300")
      expect(user.reload.ming_mode).to be false
    end
  end
end
