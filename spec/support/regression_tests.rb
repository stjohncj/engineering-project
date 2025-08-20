# Regression Test Suite
# 
# This file contains helper methods to run critical regression tests
# that ensure the API pagination and parameter handling bugs don't reoccur.

module RegressionTests
  # Run all pagination and API-related regression tests
  def self.run_all
    puts "Running critical regression tests..."
    
    test_suites = [
      # Test pagination bugs
      {
        name: "Pagination total_count accuracy",
        command: "rspec spec/controllers/api/v1/transactions_controller_spec.rb -e 'ensures total_count is never zero'"
      },
      {
        name: "Anomaly pagination accuracy", 
        command: "rspec spec/controllers/api/v1/anomaly_detections_controller_spec.rb -e 'total_count'"
      },
      
      # Test UnfilteredParameters handling
      {
        name: "Transactions parameter handling",
        command: "rspec spec/controllers/api/v1/transactions_controller_spec.rb -e 'handles unpermitted parameters'"
      },
      {
        name: "Anomalies parameter handling",
        command: "rspec spec/controllers/api/v1/anomaly_detections_controller_spec.rb -e 'unpermitted parameters'"
      },
      
      # Test dashboard integration
      {
        name: "Dashboard API integration",
        command: "rspec spec/system/dashboard_api_integration_spec.rb -e 'API consistency'"
      },
      
      # Test route matching (CSV import issue)
      {
        name: "CSV import route matching",
        command: "rspec spec/system/csv_import_spec.rb -e 'frontend calls the correct API endpoint'"
      },
      
      # Test flagged transactions endpoint
      {
        name: "Flagged transactions (anomalies) endpoint",
        command: "rspec spec/controllers/api/v1/transactions_controller_spec.rb -e 'anomalies'"
      },
      
      # Test flagged transactions review UI
      {
        name: "Flagged transactions review UI - Basic functionality",
        command: "rspec spec/system/flagged_transactions_review_spec.rb -e 'displays page header'"
      },
      
      # Test review page filtering
      {
        name: "Flagged transactions review UI - Status filtering",
        command: "rspec spec/system/flagged_transactions_review_spec.rb -e 'filters by flagged status correctly'"
      },
      
      # Test review page edit functionality 
      {
        name: "Flagged transactions review UI - Edit functionality",
        command: "rspec spec/system/flagged_transactions_review_spec.rb -e 'opens edit modal when edit button is clicked'"
      }
    ]
    
    results = []
    test_suites.each do |suite|
      puts "\n#{'-' * 50}"
      puts "Running: #{suite[:name]}"
      puts "Command: #{suite[:command]}"
      puts "#{'-' * 50}"
      
      success = system(suite[:command])
      results << { name: suite[:name], success: success }
    end
    
    puts "\n#{'=' * 60}"
    puts "REGRESSION TEST SUMMARY"
    puts "#{'=' * 60}"
    
    results.each do |result|
      status = result[:success] ? "✅ PASS" : "❌ FAIL"
      puts "#{status} - #{result[:name]}"
    end
    
    all_passed = results.all? { |r| r[:success] }
    puts "\nOverall: #{all_passed ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}"
    
    all_passed
  end
end

# Add convenience method to run from Rails console or rake task
def run_regression_tests
  RegressionTests.run_all
end