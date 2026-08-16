# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, :js) do
    DatabaseCleaner.strategy = :truncation
  end

  # For an example that has to be seen by a SECOND CONNECTION. Two connections cannot see each
  # other's uncommitted rows, so an example driving a real race has to opt out of the per-example
  # transaction twice over: `self.use_transactional_tests = false` on its own group, and this,
  # because DatabaseCleaner's own `:transaction` strategy opens one of its own around every
  # example. Truncation after the fact leaves nothing behind either way.
  config.before(:each, :truncation) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  end
end
