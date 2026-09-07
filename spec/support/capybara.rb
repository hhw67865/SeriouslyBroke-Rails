# frozen_string_literal: true

Capybara.default_max_wait_time = 5
# Let finders match aria-label so icon-only buttons are clickable by name
Capybara.enable_aria_label = true

# Headless Chrome driver
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--window-size=1400,1400")
  # ** THE BROWSER'S OWN CONSOLE, READABLE FROM A SPEC (account-openings fix round 2 — item 2). **
  # Selenium 4 does not collect Chrome's log entries unless they are asked for, so
  # `page.driver.browser.logs.get(:browser)` came back empty however loudly the page had failed —
  # which is how a Stimulus "Missing target" error rode a green suite. A JavaScript error is not a
  # broken assertion in any other spec here, so this is opt-in per example rather than a global
  # check; `spec/system/entries/form_spec.rb` is the first to read it.
  options.add_option("goog:loggingPrefs", { browser: "ALL" })

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

Capybara.javascript_driver = :selenium_chrome_headless
Capybara.default_driver = :selenium_chrome_headless

module CapybaraHelpers
  def wait_until
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until yield
    end
  end
end

RSpec.configure do |config|
  config.include CapybaraHelpers, type: :system
  config.before(:each, type: :system) do
    driven_by(:selenium_chrome_headless)
  end
  config.after(:each, type: :system) do
    Capybara.current_session.driver.quit
  end
end
