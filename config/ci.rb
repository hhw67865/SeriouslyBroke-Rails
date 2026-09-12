# frozen_string_literal: true

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Tests: databases", "bundle exec rake parallel:create parallel:prepare"
  step "Tests: RSpec", "bundle exec parallel_rspec spec"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
