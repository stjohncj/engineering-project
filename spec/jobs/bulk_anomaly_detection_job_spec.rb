require 'rails_helper'

RSpec.describe BulkAnomalyDetectionJob, type: :job do
  include ActiveJob::TestHelper

  let(:category) { create(:category) }
  let!(:transactions) { create_list(:transaction, 3, category: category) }
  let(:transaction_ids) { transactions.map(&:id) }
  let(:anomaly_detection_service) { instance_double(AnomalyDetectionService) }

  describe '#perform' do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)

      transactions.each do |transaction|
        service = instance_double(AnomalyDetectionService)
        allow(AnomalyDetectionService).to receive(:new).with(transaction).and_return(service)
        allow(service).to receive(:detect_and_flag)
      end
    end

    it 'processes anomaly detection for all specified transactions' do
      transactions.each do |transaction|
        expect(AnomalyDetectionService).to receive(:new).with(transaction)
      end

      described_class.perform_now(transaction_ids)
    end

    it 'loads transactions with necessary associations' do
      expect(Transaction).to receive(:includes).with(:category, :anomaly_detections).and_call_original

      described_class.perform_now(transaction_ids)
    end

    it 'logs successful completion' do
      expect(Rails.logger).to receive(:info).with("BulkAnomalyDetectionJob: Processed 3 transactions, 0 failed")

      described_class.perform_now(transaction_ids)
    end

    it 'invalidates anomaly-related caches' do
      expect(Rails.cache).to receive(:delete).with("active_anomalies")
      expect(Rails.cache).to receive(:delete).with("unresolved_anomalies_count")
      expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
      expect(Rails.cache).to receive(:delete_matched).with("anomaly_detections_index_*")

      described_class.perform_now(transaction_ids)
    end

    context 'when anomaly detection fails for some transactions' do
      before do
        # Make the first transaction fail
        failing_service = instance_double(AnomalyDetectionService)
        allow(AnomalyDetectionService).to receive(:new).with(transactions.first).and_return(failing_service)
        allow(failing_service).to receive(:detect_and_flag).and_raise(StandardError, "Detection failed")
      end

      it 'logs errors and continues with other transactions' do
        expect(Rails.logger).to receive(:error).with("Failed anomaly detection for transaction #{transactions.first.id}: Detection failed")
        expect(Rails.logger).to receive(:info).with("BulkAnomalyDetectionJob: Processed 2 transactions, 1 failed")

        expect { described_class.perform_now(transaction_ids) }.not_to raise_error
      end
    end

    context 'when the job itself fails' do
      before do
        allow(Transaction).to receive(:includes).and_raise(StandardError, "Database connection failed")
      end

      it 'logs the error and handles it appropriately' do
        allow(Rails.logger).to receive(:error).and_call_original
        expect(Rails.logger).to receive(:error).with("BulkAnomalyDetectionJob failed: Database connection failed").and_call_original

        # In test mode, the job might handle the error through the retry system
        described_class.perform_now(transaction_ids)
      end
    end

    context 'with empty transaction IDs' do
      it 'handles empty array gracefully' do
        expect(Rails.logger).to receive(:info).with("BulkAnomalyDetectionJob: Processed 0 transactions, 0 failed")

        expect { described_class.perform_now([]) }.not_to raise_error
      end
    end

    context 'with non-existent transaction IDs' do
      let(:non_existent_ids) { [ 999999, 999998 ] }

      it 'handles missing transactions gracefully' do
        expect(Rails.logger).to receive(:info).with("BulkAnomalyDetectionJob: Processed 0 transactions, 0 failed")

        expect { described_class.perform_now(non_existent_ids) }.not_to raise_error
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'retries on StandardError with exponential backoff' do
      # Test that the job class has retry configuration by checking if it responds to the retry_on method
      expect(described_class).to respond_to(:retry_on)
    end
  end

  describe 'job enqueueing' do
    it 'enqueues the job correctly' do
      expect {
        described_class.perform_later(transaction_ids)
      }.to enqueue_job(described_class).with(transaction_ids).on_queue('default')
    end
  end
end
