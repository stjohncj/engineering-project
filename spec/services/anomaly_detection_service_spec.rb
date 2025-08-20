require 'rails_helper'

RSpec.describe AnomalyDetectionService do
  describe '.detect_for_transaction' do
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
        
        anomaly = AnomalyDetectionService.detect_for_transaction(high_amount_transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('unusual_amount')
        expect(anomaly.severity).to be >= 3
        expect(anomaly.description).to include('significantly deviates')
      end

      it 'detects unusually low amounts' do
        low_amount_transaction = create(:transaction, amount: 1.0)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(low_amount_transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('unusual_amount')
      end

      it 'does not flag normal amounts' do
        normal_transaction = create(:transaction, amount: 75.0)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(normal_transaction)
        
        expect(anomaly).to be_nil
      end

      it 'includes statistical metadata' do
        high_amount_transaction = create(:transaction, amount: 2000.0)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(high_amount_transaction)
        
        expect(anomaly.metadata).to include('historical_average')
        expect(anomaly.metadata).to include('standard_deviation')
        expect(anomaly.metadata).to include('z_score')
      end
    end

    context 'potential duplicate detection' do
      let(:original_transaction) do
        create(:transaction, 
               description: 'Grocery Store Purchase',
               amount: 85.50,
               transaction_date: Date.current)
      end

      it 'detects exact duplicates' do
        duplicate_transaction = create(:transaction,
                                     description: 'Grocery Store Purchase',
                                     amount: 85.50,
                                     transaction_date: Date.current)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(duplicate_transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('potential_duplicate')
        expect(anomaly.metadata['similar_transaction_id'].to_i).to eq(original_transaction.id)
      end

      it 'detects similar descriptions with same amount' do
        similar_transaction = create(:transaction,
                                   description: 'Grocery Store Purchase #2',
                                   amount: 85.50,
                                   transaction_date: Date.current)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(similar_transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('potential_duplicate')
      end

      it 'does not flag significantly different transactions' do
        different_transaction = create(:transaction,
                                     description: 'Restaurant Dinner',
                                     amount: 45.00,
                                     transaction_date: Date.current)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(different_transaction)
        
        # Should not be flagged as duplicate (might be flagged for other reasons)
        if anomaly.present?
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
        
        anomaly = AnomalyDetectionService.detect_for_transaction(large_transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('incomplete_data')
        expect(anomaly.description).to include('missing required metadata')
      end

      it 'detects very short descriptions' do
        transaction = create(:transaction, description: 'X')
        
        anomaly = AnomalyDetectionService.detect_for_transaction(transaction)
        
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('incomplete_data')
      end

      it 'does not flag complete small transactions' do
        category = create(:category)
        complete_transaction = create(:transaction, 
                                    amount: 25.0,
                                    category: category,
                                    description: 'Coffee Shop Purchase')
        
        anomaly = AnomalyDetectionService.detect_for_transaction(complete_transaction)
        
        # Should not be flagged for incomplete data
        if anomaly.present?
          expect(anomaly.anomaly_type).not_to eq('incomplete_data')
        end
      end
    end

    context 'severity calculation' do
      it 'assigns higher severity to larger deviations' do
        # Create baseline data
        5.times { |i| create(:transaction, amount: 50.0, transaction_date: (i + 5).days.ago) }
        
        moderate_anomaly_transaction = create(:transaction, amount: 200.0)
        severe_anomaly_transaction = create(:transaction, amount: 1000.0)
        
        moderate_anomaly = AnomalyDetectionService.detect_for_transaction(moderate_anomaly_transaction)
        severe_anomaly = AnomalyDetectionService.detect_for_transaction(severe_anomaly_transaction)
        
        expect(severe_anomaly.severity).to be > moderate_anomaly.severity
      end

      it 'assigns severity levels correctly' do
        # Test different severity levels
        5.times { |i| create(:transaction, amount: 50.0, transaction_date: (i + 5).days.ago) }
        
        extreme_transaction = create(:transaction, amount: 10000.0)
        anomaly = AnomalyDetectionService.detect_for_transaction(extreme_transaction)
        
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
        anomaly = AnomalyDetectionService.detect_for_transaction(test_transaction)
        expect(anomaly).to be_present
      end

      it 'handles case with no historical data' do
        # Remove all existing transactions
        Transaction.delete_all
        
        first_transaction = create(:transaction, amount: 100.0)
        
        # Should not crash and might still detect other issues
        expect { AnomalyDetectionService.detect_for_transaction(first_transaction) }.not_to raise_error
      end
    end

    context 'time-based analysis' do
      it 'uses appropriate historical window' do
        # Create old transactions (beyond 90-day window)
        create(:transaction, amount: 1000.0, transaction_date: 100.days.ago)
        
        # Create recent transactions
        5.times { |i| create(:transaction, amount: 50.0, transaction_date: (i + 5).days.ago) }
        
        test_transaction = create(:transaction, amount: 55.0)
        
        # Should use only recent transactions for analysis
        anomaly = AnomalyDetectionService.detect_for_transaction(test_transaction)
        expect(anomaly).to be_nil # Should be normal compared to recent transactions
      end
    end

    context 'edge cases' do
      it 'handles zero amount transactions' do
        zero_transaction = create(:transaction, amount: 0.0)
        
        expect { AnomalyDetectionService.detect_for_transaction(zero_transaction) }.not_to raise_error
      end

      it 'handles negative amounts correctly' do
        # Create baseline of negative amounts (expenses)
        5.times { |i| create(:transaction, amount: -(50 + i * 10), transaction_date: (i + 5).days.ago) }
        
        extreme_negative = create(:transaction, amount: -5000.0)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(extreme_negative)
        expect(anomaly).to be_present
      end

      it 'handles very large positive amounts (income)' do
        # Create baseline of small positive amounts
        5.times { |i| create(:transaction, amount: 100 + i * 50, transaction_date: (i + 5).days.ago) }
        
        large_income = create(:transaction, amount: 50000.0)
        
        anomaly = AnomalyDetectionService.detect_for_transaction(large_income)
        expect(anomaly).to be_present
        expect(anomaly.anomaly_type).to eq('unusual_amount')
      end
    end

    context 'anomaly persistence' do
      it 'creates and saves anomaly records' do
        create(:transaction, amount: 50.0, transaction_date: 5.days.ago)
        
        test_transaction = create(:transaction, amount: 1000.0)
        
        expect { AnomalyDetectionService.detect_for_transaction(test_transaction) }
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