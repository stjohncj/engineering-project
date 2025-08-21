# Override the default 'test' task to run RSpec instead of the default Rails test suite
Rake::Task[:test].clear if Rake::Task.task_defined?(:test)

desc "Run all RSpec tests (excluding system tests)"
task :test => :environment do
  puts "Running RSpec tests (excluding system tests)..."
  exit_code = system("bundle exec rspec --exclude-pattern 'spec/system/**/*_spec.rb'")
  exit(exit_code ? 0 : 1)
end

# Also provide a namespace for more specific test running
namespace :test do
  desc "Run RSpec tests with detailed output"
  task :verbose => :environment do
    puts "Running RSpec tests with detailed output..."
    exit_code = system("bundle exec rspec --format documentation")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run RSpec tests and generate coverage report"
  task :coverage => :environment do
    ENV['COVERAGE'] = 'true'
    puts "Running RSpec tests with coverage..."
    exit_code = system("bundle exec rspec")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run only failing RSpec tests"
  task :failures => :environment do
    puts "Running only failing RSpec tests..."
    exit_code = system("bundle exec rspec --only-failures")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run RSpec tests for controllers only"
  task :controllers => :environment do
    puts "Running controller tests..."
    exit_code = system("bundle exec rspec spec/controllers")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run RSpec tests for models only"
  task :models => :environment do
    puts "Running model tests..."
    exit_code = system("bundle exec rspec spec/models")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run RSpec tests for services only"
  task :services => :environment do
    puts "Running service tests..."
    exit_code = system("bundle exec rspec spec/services")
    exit(exit_code ? 0 : 1)
  end
  
  desc "Run RSpec system tests only"
  task :system => :environment do
    puts "Running system tests..."
    exit_code = system("bundle exec rspec spec/system")
    exit(exit_code ? 0 : 1)
  end
end