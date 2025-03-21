# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :chrome, screen_size: [1920, 1080]
  end

  config.before(:each, :js, type: :system) do
    driven_by :selenium_chrome_headless
  end
end

module CapybaraHelpers
  def wait_until
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until yield
    end
  end
end

RSpec.configure do |config|
  config.include CapybaraHelpers, type: :system
end
