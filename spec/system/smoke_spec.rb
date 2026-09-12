# frozen_string_literal: true

require "rails_helper"

# Two examples that prove the two drivers: the in-process one renders a page, the browser one
# runs JavaScript. Everything else about the app is proven elsewhere.
RSpec.describe "Test drivers", type: :system do
  it "renders the sign-in page in-process", :aggregate_failures do
    visit new_user_session_path

    expect(page).to have_field("Email")
    expect(Capybara.current_driver).to eq(:rack_test)
  end

  it "runs JavaScript in one headless Chrome", :aggregate_failures, :js do
    visit new_user_session_path

    expect(page.evaluate_script("1 + 1")).to eq(2)
    expect(Capybara.current_driver).to eq(:selenium_chrome_headless)
  end
end
