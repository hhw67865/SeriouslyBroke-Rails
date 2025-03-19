require 'simplecov'

# Save to CircleCI's coverage directory if we're on CircleCI
if ENV['CI']
  SimpleCov.coverage_dir(File.join('coverage', ENV['CIRCLE_NODE_INDEX'].to_s)) if ENV['CIRCLE_NODE_INDEX']
end

SimpleCov.start 'rails' do
  # Standard filters
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/coverage/'
  
  # Group by component type
  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Helpers', 'app/helpers'
  add_group 'Libraries', 'lib'
  add_group 'Jobs', 'app/jobs'
  add_group 'Mailers', 'app/mailers'
  add_group 'Policies', 'app/policies'
  add_group 'Services', 'app/services'
  
  # Minimum coverage percentage
  minimum_coverage 90
  
  # Don't show files with no coverage in report
  skip_empty_source_files true
end 