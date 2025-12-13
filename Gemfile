# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.2.2"

# Core Rails gems
gem "bootsnap", require: false
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "rails", "8.1.1"
gem "sprockets-rails"

# Frontend and Asset Pipeline
gem "importmap-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "turbo-rails"

# Authentication and Authorization
gem "devise", "~> 4.9"

# Pagination
gem "kaminari", "~> 1.2"

# Windows compatibility
gem "tzinfo-data", platforms: [:windows, :jruby]

group :development, :test do
  # Debugging and Testing
  gem "debug", platforms: [:mri, :windows]
  gem "rspec-rails", "~> 7.1"

  # Test Data Generation
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"

  # Development Tools
  gem "byebug"
  gem "pry-rails", "~> 0.3.11"
end

group :development do
  # Development Assistance
  gem "annotate"
  gem "bullet"
  gem "web-console"

  # Code Quality
  gem "rubocop"
  gem "rubocop-erb"
  gem "rubocop-performance"
  gem "rubocop-rails"
  gem "rubocop-rspec"
end

group :test do
  # System/Integration Testing
  gem "capybara"
  gem "selenium-webdriver"

  # Testing Support
  gem "database_cleaner-active_record", "~> 2.2"
  gem "shoulda-matchers", "~> 6.4"
end

gem "chartkick"
gem "groupdate"
gem "heroicon"
gem "simple_form", "~> 5.3"
