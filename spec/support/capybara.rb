# frozen_string_literal: true

Capybara.default_max_wait_time = 5
# Let finders match aria-label so icon-only buttons are clickable by name.
Capybara.enable_aria_label = true

Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--window-size=1400,1400")
  options.add_option("goog:loggingPrefs", { browser: "ALL" })

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

Capybara.javascript_driver = :selenium_chrome_headless

module CapybaraHelpers
  def wait_until
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until yield
    end
  end
end

# Rack::Test unless an example says :js. One Chrome per process: Capybara resets the session
# between examples, and restarting the browser cost a second per example.
RSpec.configure do |config|
  config.include CapybaraHelpers, type: :system
  config.before(:each, type: :system) { driven_by(:rack_test) }
  config.before(:each, :js, type: :system) { driven_by(:selenium_chrome_headless) }
end
