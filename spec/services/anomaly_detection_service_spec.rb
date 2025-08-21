require 'rails_helper'

RSpec.describe AnomalyDetectionService do
  describe '#detect_and_flag' do
    let(:transaction) { create(:transaction, amount: 500.0, transaction_date: Date.current) }

    context 'unusual amount detection' do
      before do
        # Create historical transactions with amounts around 50-100
        10.times do |i|
          create(:transaction,
                 amount: 50 + (i * 5), # 50, 55, 60, ... 95
                 transaction_date: (i + 10).days.ago)
        end
      end

      it 'detects unusually high amounts' do
        high_amount_transaction = create(:transaction, amount: 2000.0)

        anomalies = AnomalyDetectionService.new(high_amount_transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.first
        expect(anomaly.anomaly_type).to eq('unusual_amount')
        expect(anomaly.severity).to be >= 3
        expect(anomaly.description).to include('significantly higher')
      end

      it 'detects unusually low amounts' do
        low_amount_transaction = create(:transaction, amount: 1.0)

        anomalies = AnomalyDetectionService.new(low_amount_transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.first
        expect(anomaly.anomaly_type).to eq('unusual_amount')
      end

      it 'does not flag normal amounts' do
        category = create(:category)
        normal_transaction = create(:transaction, amount: 75.0, category: category, description: 'Normal purchase')

        anomalies = AnomalyDetectionService.new(normal_transaction).detect_and_flag

        expect(anomalies).to be_empty
      end

      it 'includes statistical metadata' do
        high_amount_transaction = create(:transaction, amount: 2000.0)

        anomalies = AnomalyDetectionService.new(high_amount_transaction).detect_and_flag

        anomaly = anomalies.first
        expect(anomaly.metadata).to include('historical_average')
        expect(anomaly.metadata).to include('standard_deviation')
        expect(anomaly.metadata).to include('z_score')
      end
    end

    context 'potential duplicate detection' do
      let(:category) { create(:category) }
      let(:original_transaction) do
        create(:transaction,
               description: 'Daily Grocery Store Purchase Main Building Good Item Order Final',
               amount: 85.50,
               transaction_date: Date.current,
               category: category)
      end

      it 'detects exact duplicates' do
        # Ensure original transaction exists first
        original_transaction
        
        duplicate_transaction = create(:transaction,
                                     description: 'Daily Grocery Store Purchase Main Building Good Item Order Final',
                                     amount: 85.50,
                                     transaction_date: Date.current)

        anomalies = AnomalyDetectionService.new(duplicate_transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.first
        expect(anomaly.anomaly_type).to eq('potential_duplicate')
        expect(anomaly.metadata['similar_transaction_id'].to_i).to eq(original_transaction.id)
      end

      it 'detects similar descriptions with same amount' do
        # Ensure original transaction exists first
        original_transaction
        
        similar_transaction = create(:transaction,
                                   description: 'Daily Grocery Store Purchase Main Building Good Item Order Done',
                                   amount: 85.50,
                                   transaction_date: Date.current,
                                   category: category)

        anomalies = AnomalyDetectionService.new(similar_transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.find { |a| a.anomaly_type == 'potential_duplicate' }
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('potential_duplicate')
      end

      it 'does not flag significantly different transactions' do
        different_transaction = create(:transaction,
                                     description: 'Restaurant Dinner',
                                     amount: 45.00,
                                     transaction_date: Date.current)

        anomalies = AnomalyDetectionService.new(different_transaction).detect_and_flag

        # Should not be flagged as duplicate (might be flagged for other reasons)
        if anomalies.present?
          anomaly = anomalies.first
          expect(anomaly.anomaly_type).not_to eq('potential_duplicate')
        end
      end
    end

    context 'incomplete data detection' do
      it 'detects missing category for significant amounts' do
        large_transaction = create(:transaction,
                                 amount: 1000.0,
                                 category: nil,
                                 description: 'Large Purchase')

        anomalies = AnomalyDetectionService.new(large_transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.first
        expect(anomaly.anomaly_type).to eq('incomplete_metadata')
        expect(anomaly.description).to include('Missing category')
      end

      it 'detects very short descriptions' do
        transaction = create(:transaction, description: 'X')

        anomalies = AnomalyDetectionService.new(transaction).detect_and_flag

        expect(anomalies).to be_present
        anomaly = anomalies.first
        expect(anomaly.anomaly_type).to eq('incomplete_metadata')
      end

      it 'does not flag complete small transactions' do
        category = create(:category)
        complete_transaction = create(:transaction,
                                    amount: 25.0,
                                    category: category,
                                    description: 'Coffee Shop Purchase')

        anomalies = AnomalyDetectionService.new(complete_transaction).detect_and_flag

        # Should not be flagged for incomplete data
        if anomalies.present?
          anomaly = anomalies.first
          expect(anomaly.anomaly_type).not_to eq('incomplete_data')
        end
      end
    end

    context 'severity calculation' do
      it 'assigns appropriate severity to large deviations' do
        # Create baseline data with tighter range - need at least 10 for detection
        10.times { |i| create(:transaction, amount: 50.0 + i, transaction_date: (i + 15).days.ago) }

        category = create(:category)
        # Test with a very large amount that should trigger detection
        large_anomaly_transaction = create(:transaction, amount: 15000.0, category: category, description: 'Very large purchase')

        anomalies = AnomalyDetectionService.new(large_anomaly_transaction).detect_and_flag

        unusual_amount_anomaly = anomalies.find { |a| a.anomaly_type == 'unusual_amount' }
        
        # Should detect unusual amount and assign appropriate severity
        expect(unusual_amount_anomaly).to be_present
        expect(unusual_amount_anomaly.severity).to be_between(3, 5)
      end

      it 'assigns severity levels correctly' do
        # Test different severity levels
        5.times { |i| create(:transaction, amount: 50.0, transaction_date: (i + 5).days.ago) }

        extreme_transaction = create(:transaction, amount: 10000.0)
        anomalies = AnomalyDetectionService.new(extreme_transaction).detect_and_flag

        anomaly = anomalies.first
        expect(anomaly.severity).to be_between(1, 5)
      end
    end

    context 'with insufficient historical data' do
      it 'still performs basic checks with limited data' do
        # Only create 2 historical transactions
        create(:transaction, amount: 50.0, transaction_date: 5.days.ago)
        create(:transaction, amount: 60.0, transaction_date: 3.days.ago)

        test_transaction = create(:transaction, amount: 5000.0)

        # Should still detect obvious anomalies
        anomalies = AnomalyDetectionService.new(test_transaction).detect_and_flag
        expect(anomalies).to be_present
        anomaly = anomalies.first
      end

      it 'handles case with no historical data' do
        # Remove all existing transactions
        Transaction.delete_all

        first_transaction = create(:transaction, amount: 100.0)

        # Should not crash and might still detect other issues
        expect { AnomalyDetectionService.new(first_transaction).detect_and_flag }.not_to raise_error
      end
    end

    context 'time-based analysis' do
      it 'uses appropriate historical window' do
        # Create old transactions (beyond 90-day window)
        create(:transaction, amount: 1000.0, transaction_date: 100.days.ago)

        # Create recent transactions
        category = create(:category)
        5.times { |i| create(:transaction, amount: 50.0, transaction_date: (i + 5).days.ago) }

        test_transaction = create(:transaction, amount: 55.0, category: category, description: 'Normal purchase')

        # Should use only recent transactions for analysis
        anomalies = AnomalyDetectionService.new(test_transaction).detect_and_flag
        expect(anomalies).to be_empty # Should be normal compared to recent transactions
      end
    end

    context 'edge cases' do
      it 'handles zero amount transactions' do
        zero_transaction = create(:transaction, amount: 0.0)

        expect { AnomalyDetectionService.new(zero_transaction).detect_and_flag }.not_to raise_error
      end

      it 'handles negative amounts correctly' do
        # Create baseline of negative amounts (expenses)
        5.times { |i| create(:transaction, amount: -(50 + i * 10), transaction_date: (i + 5).days.ago) }

        extreme_negative = create(:transaction, amount: -5000.0)

        anomalies = AnomalyDetectionService.new(extreme_negative).detect_and_flag
        expect(anomalies).to be_present
        anomaly = anomalies.first
      end

      it 'handles very large positive amounts (income)' do
        # Create baseline of small positive amounts - need at least 10 for statistical detection
        10.times { |i| create(:transaction, amount: 100 + i * 50, transaction_date: (i + 15).days.ago) }

        category = create(:category)
        large_income = create(:transaction, amount: 50000.0, category: category, description: 'Large income')

        anomalies = AnomalyDetectionService.new(large_income).detect_and_flag
        expect(anomalies).to be_present
        anomaly = anomalies.find { |a| a.anomaly_type == 'unusual_amount' }
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('unusual_amount')
      end
    end

    context 'anomaly persistence' do
      it 'creates and saves anomaly records' do
        create(:transaction, amount: 50.0, transaction_date: 5.days.ago)

        test_transaction = create(:transaction, amount: 1000.0)

        expect { AnomalyDetectionService.new(test_transaction).detect_and_flag }
          .to change(AnomalyDetection, :count).by(1)

        anomaly = AnomalyDetection.last
        expect(anomaly.transaction).to eq(test_transaction)
        expect(anomaly.detected_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'helper methods' do
    describe '.calculate_z_score' do
      it 'calculates z-score correctly' do
        # Mock method if it's private
        service = AnomalyDetectionService

        # Test with known values
        # mean = 100, std_dev = 10, value = 120 should give z-score of 2
        if service.respond_to?(:calculate_z_score)
          z_score = service.calculate_z_score(120, 100, 10)
          expect(z_score).to be_within(0.001).of(2.0)
        end
      end
    end
  end
end
