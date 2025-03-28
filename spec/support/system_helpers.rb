# frozen_string_literal: true

require "action_view" # Ensure ActionView helpers are loaded

RSpec.configure do |config|
  # Include number helpers (like number_to_currency) in system specs
  config.include ActionView::Helpers::NumberHelper, type: :system
end
