source "https://rubygems.org"

ruby "3.2.2"

# Core Rails gems
gem "rails", "~> 7.1.5", ">= 7.1.5.1"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

# Frontend and Asset Pipeline
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Authentication
gem "devise", "~> 4.9"

# Windows compatibility
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # Debugging and Testing
  gem "debug", platforms: %i[ mri windows ]
  gem "rspec-rails", "~> 7.1"
  
  # Test Data Generation
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  
  # Development Tools
  gem "pry-rails", "~> 0.3.11"
end

group :development do
  # Development Assistance
  gem "web-console"
  gem "annotate", "~> 3.2"
  gem "bullet", "~> 8.0"
  
  # Code Quality
  gem "rubocop", "~> 1.74"
  gem "rubocop-rails", "~> 2.30"
  gem "rubocop-rspec", "~> 3.5"
end

group :test do
  # System/Integration Testing
  gem "capybara"
  gem "selenium-webdriver"
  
  # Testing Support
  gem "shoulda-matchers", "~> 6.4"
  gem "simplecov", "~> 0.22.0"
  gem "database_cleaner-active_record", "~> 2.2"
end

gem "simple_form", "~> 5.3"
