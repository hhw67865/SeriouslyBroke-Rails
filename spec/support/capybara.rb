# frozen_string_literal: true

Capybara.default_max_wait_time = 5

# Headless Chrome driver
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1400,1400")

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
end
