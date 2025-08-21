require 'rails_helper'

RSpec.describe AnomalyDetectionJob, type: :job do
  include ActiveJob::TestHelper

  let(:category) { create(:category) }
  let(:transaction) { create(:transaction, category: category) }
  let(:anomaly_detection_service) { instance_double(AnomalyDetectionService) }

  describe '#perform' do
    before do
      allow(AnomalyDetectionService).to receive(:new).with(transaction).and_return(anomaly_detection_service)
      allow(anomaly_detection_service).to receive(:detect_and_flag)
    end

    it 'processes anomaly detection for the given transaction' do
      expect(AnomalyDetectionService).to receive(:new).with(transaction)
      expect(anomaly_detection_service).to receive(:detect_and_flag)

      described_class.perform_now(transaction.id)
    end

    it 'invalidates anomaly-related caches' do
      expect(Rails.cache).to receive(:delete).with("active_anomalies")
      expect(Rails.cache).to receive(:delete).with("unresolved_anomalies_count")
      expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
      expect(Rails.cache).to receive(:delete_matched).with("anomaly_detections_index_*")

      described_class.perform_now(transaction.id)
    end

    context 'when transaction is not found' do
      it 'logs a warning and does not raise an error' do
        non_existent_id = 999999

        expect(Rails.logger).to receive(:warn).with("AnomalyDetectionJob: Transaction #{non_existent_id} not found")
        expect { described_class.perform_now(non_existent_id) }.not_to raise_error
      end
    end

    context 'when anomaly detection service raises an error' do
      let(:error_message) { "Service error" }

      before do
        allow(anomaly_detection_service).to receive(:detect_and_flag).and_raise(StandardError, error_message)
      end

      it 'logs the error and re-raises it for retry logic' do
        expect(Rails.logger).to receive(:error).with("AnomalyDetectionJob failed for transaction #{transaction.id}: #{error_message}")

        expect { described_class.perform_now(transaction.id) }.to raise_error(StandardError, error_message)
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'retries on StandardError with exponential backoff' do
      expect(described_class.retry_on).to include(StandardError)
    end
  end

  describe 'job enqueueing' do
    it 'enqueues the job correctly' do
      expect {
        described_class.perform_later(transaction.id)
      }.to enqueue_job(described_class).with(transaction.id).on_queue('default')
    end
  end
end
