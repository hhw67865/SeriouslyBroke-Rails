# frozen_string_literal: true

require "rails_helper"

# The new-entry form pre-fills its date with the user-local "today"
# (app/views/entries/_form.html.erb). It is the simplest browser-observable
# surface that proves the around-action localized the whole request.
RSpec.describe "Timezone localization", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { sign_in user, scope: :user }

  context "when the user has a timezone west of UTC" do
    let(:user) { create(:user, timezone: "America/New_York") }

    it "defaults the new-entry date to the user's local day, not the UTC day" do
      # 2026-04-16 01:00 UTC == 2026-04-15 21:00 in America/New_York
      travel_to Time.utc(2026, 4, 16, 1, 0) do
        visit new_entry_path
        expect(page).to have_field("Date", with: "2026-04-15")
      end
    end
  end

  context "when the user has no timezone set" do
    let(:user) { create(:user, timezone: nil) }

    it "falls back to the UTC day" do
      travel_to Time.utc(2026, 4, 16, 1, 0) do
        visit new_entry_path
        expect(page).to have_field("Date", with: "2026-04-16")
      end
    end
  end

  context "when the user is on a month boundary (west of UTC)" do
    let(:user) { create(:user, timezone: "America/New_York") }

    it "defaults the dashboard selected month to the user-local month, not UTC", :aggregate_failures do
      # 2026-05-01 01:00 UTC == 2026-04-30 21:00 in America/New_York
      # UTC month = May, user-local month = April
      travel_to Time.utc(2026, 5, 1, 1, 0) do
        visit authenticated_root_path
        expect(page).to have_content("April 2026")
        expect(page).not_to have_content("May 2026")
      end
    end
  end
end
