require 'rails_helper'

RSpec.describe 'Rule Application Integration', type: :integration do
  describe 'end-to-end rule application during transaction processing' do
    let(:csv_content) do
      <<~CSV
        amount,description,date,category
        15.99,Amazon Prime Subscription,2024-01-15,
        75.50,Starbucks Coffee,2024-01-16,
        1250.00,Laptop Purchase,2024-01-17,
        25.99,McDonald's Meal,2024-01-18,
      CSV
    end

    before do
      # Create some base categories
      create(:category, name: 'Shopping')
      create(:category, name: 'Food & Dining')

      # Create rules that should apply to the CSV data
      @amazon_rule = create(:rule,
        name: 'Amazon Categorization',
        condition_field: 'description',
        condition_operator: 'contains',
        condition_value: 'Amazon',
        action_type: 'categorize',
        action_value: 'Shopping',
        active: true
      )

      @coffee_rule = create(:rule,
        name: 'Coffee Shop Categorization',
        condition_field: 'description',
        condition_operator: 'contains',
        condition_value: 'Starbucks',
        action_type: 'categorize',
        action_value: 'Coffee & Beverages',
        active: true
      )

      @high_value_rule = create(:rule,
        name: 'High Value Flagging',
        condition_field: 'amount',
        condition_operator: 'greater_than',
        condition_value: '1000',
        action_type: 'flag',
        action_value: 'High Value Purchase',
        active: true
      )

      @food_rule = create(:rule,
        name: 'Fast Food Categorization',
        condition_field: 'description',
        condition_operator: 'contains',
        condition_value: 'McDonald',
        action_type: 'categorize',
        action_value: 'Food & Dining',
        active: true
      )
    end

    it 'applies rules during CSV import and anomaly detection processing' do
      # Create a temporary CSV file
      csv_file = Tempfile.new([ 'test_transactions', '.csv' ])
      csv_file.write(csv_content)
      csv_file.rewind

      # Import the CSV
      service = CsvImportService.new(csv_file)
      result = service.import

      expect(result[:imported]).to eq(4)
      expect(result[:failed]).to eq(0)

      # Get the imported transactions
      imported_transactions = Transaction.where(import_batch_id: result[:batch_id])
      expect(imported_transactions.count).to eq(4)

      # Manually run the anomaly detection jobs that would normally run in background
      imported_transactions.each do |transaction|
        AnomalyDetectionService.new(transaction).detect_and_flag
      end

      # Reload transactions to get updated data
      imported_transactions = imported_transactions.reload

      # Verify Amazon rule was applied
      amazon_transaction = imported_transactions.find_by(description: 'Amazon Prime Subscription')
      expect(amazon_transaction.category.name).to eq('Shopping')

      # Verify Coffee rule was applied and created new category
      starbucks_transaction = imported_transactions.find_by(description: 'Starbucks Coffee')
      expect(starbucks_transaction.category.name).to eq('Coffee & Beverages')
      expect(Category.find_by(name: 'Coffee & Beverages')).to be_present

      # Verify high value rule was applied
      laptop_transaction = imported_transactions.find_by(description: 'Laptop Purchase')
      expect(laptop_transaction.status).to eq('flagged')

      # Check that a rule-based anomaly was created
      rule_anomaly = laptop_transaction.anomaly_detections.find_by(anomaly_type: 'rule_based')
      expect(rule_anomaly).to be_present
      expect(rule_anomaly.description).to include('High Value Flagging')

      # Verify food rule was applied
      mcdonalds_transaction = imported_transactions.find_by(description: "McDonald's Meal")
      expect(mcdonalds_transaction.category.name).to eq('Food & Dining')

      csv_file.close
      csv_file.unlink
    end

    it 'does not apply inactive rules' do
      # Deactivate one of the rules
      @amazon_rule.update!(active: false)

      csv_file = Tempfile.new([ 'test_transactions', '.csv' ])
      csv_file.write(csv_content)
      csv_file.rewind

      service = CsvImportService.new(csv_file)
      result = service.import

      # Run anomaly detection
      imported_transactions = Transaction.where(import_batch_id: result[:batch_id])
      imported_transactions.each do |transaction|
        AnomalyDetectionService.new(transaction).detect_and_flag
      end

      # Amazon rule should not have been applied
      amazon_transaction = imported_transactions.find_by(description: 'Amazon Prime Subscription')
      expect(amazon_transaction.category).to be_nil

      # But other active rules should still work
      starbucks_transaction = imported_transactions.find_by(description: 'Starbucks Coffee')
      expect(starbucks_transaction.category.name).to eq('Coffee & Beverages')

      csv_file.close
      csv_file.unlink
    end

    it 'handles multiple rules applying to the same transaction' do
      # Create an additional rule that could apply to the laptop purchase
      create(:rule,
        name: 'Electronics Categorization',
        condition_field: 'description',
        condition_operator: 'contains',
        condition_value: 'Laptop',
        action_type: 'categorize',
        action_value: 'Electronics',
        active: true
      )

      csv_file = Tempfile.new([ 'test_transactions', '.csv' ])
      csv_file.write(csv_content)
      csv_file.rewind

      service = CsvImportService.new(csv_file)
      result = service.import

      # Run anomaly detection
      imported_transactions = Transaction.where(import_batch_id: result[:batch_id])
      imported_transactions.each do |transaction|
        AnomalyDetectionService.new(transaction).detect_and_flag
      end

      laptop_transaction = imported_transactions.find_by(description: 'Laptop Purchase')

      # Should be categorized by the Electronics rule
      expect(laptop_transaction.category.name).to eq('Electronics')

      # Should also be flagged by the high value rule
      expect(laptop_transaction.status).to eq('flagged')

      # Should have a rule-based anomaly
      rule_anomaly = laptop_transaction.anomaly_detections.find_by(anomaly_type: 'rule_based')
      expect(rule_anomaly).to be_present

      csv_file.close
      csv_file.unlink
    end

    it 'works with the existing anomaly detection' do
      # Create transactions that will trigger both rules and anomalies
      csv_with_anomalies = <<~CSV
        amount,description,date,category
        15000.00,Amazon Expensive Item,2024-01-15,
        5.99,Starbucks Coffee,2024-01-16,
        5.99,Starbucks Coffee,2024-01-16,
      CSV

      # Create some historical data for anomaly detection (need at least 10 for statistical analysis)
      10.times do |i|
        create(:transaction, amount: 50.0 + (i * 10), transaction_date: (30 - i).days.ago)
      end

      csv_file = Tempfile.new([ 'test_transactions', '.csv' ])
      csv_file.write(csv_with_anomalies)
      csv_file.rewind

      service = CsvImportService.new(csv_file)
      result = service.import

      # Run anomaly detection
      imported_transactions = Transaction.where(import_batch_id: result[:batch_id])
      imported_transactions.each do |transaction|
        AnomalyDetectionService.new(transaction).detect_and_flag
      end

      expensive_transaction = imported_transactions.find_by(description: 'Amazon Expensive Item')

      # Should be categorized by rule
      expect(expensive_transaction.category.name).to eq('Shopping')

      # Should be flagged (by both high value rule and unusual amount detection)
      expect(expensive_transaction.status).to eq('flagged')

      # Should have multiple anomalies
      anomalies = expensive_transaction.anomaly_detections
      expect(anomalies.count).to be >= 2

      # Should have both rule-based and unusual_amount anomalies
      expect(anomalies.pluck(:anomaly_type)).to include('rule_based', 'unusual_amount')

      # Duplicate detection should also work
      duplicate_transactions = imported_transactions.where(description: 'Starbucks Coffee')
      expect(duplicate_transactions.count).to eq(2)

      # At least one should have a duplicate anomaly
      duplicate_anomalies = AnomalyDetection.where(
        transaction_record: duplicate_transactions,
        anomaly_type: 'potential_duplicate'
      )
      expect(duplicate_anomalies.count).to be >= 1

      csv_file.close
      csv_file.unlink
    end
  end
end
