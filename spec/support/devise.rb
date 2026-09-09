# frozen_string_literal: true

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :system
  # Request specs sign in the same way. Used where the assertion is about the wire — a
  # permitted-parameter list, say — which no browser test can reach until a form renders it.
  config.include Devise::Test::IntegrationHelpers, type: :request
end
