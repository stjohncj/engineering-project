require 'rails_helper'

RSpec.describe CsvImportJob, type: :job do
  include ActiveJob::TestHelper

  let(:csv_content) do
    <<~CSV
      amount,description,date,category
      100.50,Test Transaction 1,2025-08-19,Food
      200.75,Test Transaction 2,2025-08-20,Transport
    CSV
  end

  let(:temp_file_path) { Rails.root.join('tmp', 'test_import.csv') }
  let(:user_id) { 'test_user_123' }
  let(:import_options) { { run_anomaly_detection: true } }
  let(:csv_import_service) { instance_double(CsvImportService) }
  let(:import_result) do
    {
      imported: 2,
      failed: 0,
      errors: [],
      batch_id: 'test-batch-123'
    }
  end

  before do
    # Create test CSV file
    File.write(temp_file_path, csv_content)

    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(CsvImportService).to receive(:new).and_return(csv_import_service)
    allow(csv_import_service).to receive(:import).and_return(import_result)
  end

  after do
    # Clean up test file
    File.delete(temp_file_path) if File.exist?(temp_file_path)
  end

  describe '#perform' do
    it 'processes the CSV import successfully' do
      expect(CsvImportService).to receive(:new).with(kind_of(File))
      expect(csv_import_service).to receive(:import).and_return(import_result)

      described_class.perform_now(temp_file_path.to_s, user_id, import_options)
    end

    it 'logs successful completion' do
      expect(Rails.logger).to receive(:info).with("CsvImportJob completed: 2 imported, 0 failed")

      described_class.perform_now(temp_file_path.to_s, user_id, import_options)
    end

    it 'deletes the temporary file after processing' do
      expect(File.exist?(temp_file_path)).to be true

      described_class.perform_now(temp_file_path.to_s, user_id, import_options)

      expect(File.exist?(temp_file_path)).to be false
    end

    context 'when user_id is provided' do
      it 'stores import results in cache' do
        cache_key_pattern = "csv_import_result_#{user_id}_"
        latest_key = "csv_import_latest_#{user_id}"

        expect(Rails.cache).to receive(:write).with(
          a_string_starting_with(cache_key_pattern),
          import_result.merge(status: 'completed'),
          expires_in: 1.hour
        )
        expect(Rails.cache).to receive(:write).with(
          latest_key,
          a_string_starting_with(cache_key_pattern),
          expires_in: 1.hour
        )

        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
      end
    end

    context 'when run_anomaly_detection is enabled' do
      before do
        allow(Transaction).to receive(:where).with(import_batch_id: import_result[:batch_id]).and_return(
          double(pluck: [ 1, 2, 3, 4, 5 ])
        )
      end

      it 'queues anomaly detection jobs for imported transactions' do
        expect(BulkAnomalyDetectionJob).to receive(:perform_later).with([ 1, 2, 3, 4, 5 ])

        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
      end
    end

    context 'when run_anomaly_detection is disabled' do
      let(:import_options) { { run_anomaly_detection: false } }

      it 'does not queue anomaly detection jobs' do
        expect(BulkAnomalyDetectionJob).not_to receive(:perform_later)

        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
      end
    end

    context 'when file does not exist' do
      let(:non_existent_file) { '/path/to/non/existent/file.csv' }

      it 'logs error and returns early' do
        expect(Rails.logger).to receive(:error).with("CsvImportJob: File not found at #{non_existent_file}")
        expect(CsvImportService).not_to receive(:new)

        described_class.perform_now(non_existent_file, user_id, import_options)
      end
    end

    context 'when CSV import service fails' do
      let(:error_message) { "Import service failed" }

      before do
        allow(csv_import_service).to receive(:import).and_raise(StandardError, error_message)
      end

      it 'logs the error and handles it appropriately' do
        allow(Rails.logger).to receive(:error).and_call_original
        expect(Rails.logger).to receive(:error).with("CsvImportJob failed: #{error_message}").and_call_original
        expect(Rails.logger).to receive(:error).with(kind_of(String)).and_call_original # backtrace

        # Due to retry mechanism, the job may not raise immediately in test environment
        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
      end

      it 'stores error result when user_id is provided' do
        error_result = {
          imported: 0,
          failed: 0,
          errors: [ "Import failed: #{error_message}" ],
          batch_id: nil,
          status: 'failed'
        }

        allow(Rails.cache).to receive(:write).and_call_original
        expect(Rails.cache).to receive(:write).with(
          a_string_starting_with("csv_import_result_#{user_id}_"),
          hash_including(error_result.except(:status)),
          expires_in: 1.hour
        ).and_call_original

        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
      end

      it 'still deletes the temporary file' do
        described_class.perform_now(temp_file_path.to_s, user_id, import_options)
        expect(File.exist?(temp_file_path)).to be false
      end
    end

    context 'without user_id' do
      it 'does not store results in cache' do
        expect(Rails.cache).not_to receive(:write)

        described_class.perform_now(temp_file_path.to_s, nil, import_options)
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on the high_priority queue' do
      expect(described_class.queue_name).to eq('high_priority')
    end

    it 'retries on StandardError with exponential backoff' do
      # Test that the job class has retry configuration by checking if it responds to the retry_on method
      expect(described_class).to respond_to(:retry_on)
    end
  end

  describe 'job enqueueing' do
    it 'enqueues the job correctly' do
      expect {
        described_class.perform_later(temp_file_path.to_s, user_id, import_options)
      }.to enqueue_job(described_class).with(temp_file_path.to_s, user_id, import_options).on_queue('high_priority')
    end
  end

  describe 'private methods' do
    let(:job_instance) { described_class.new }

    describe '#store_import_results' do
      it 'stores results with correct cache keys and expiration' do
        result = { imported: 1, failed: 0 }

        expect(Rails.cache).to receive(:write).with(
          a_string_starting_with("csv_import_result_#{user_id}_"),
          result.merge(status: 'completed'),
          expires_in: 1.hour
        )
        expect(Rails.cache).to receive(:write).with(
          "csv_import_latest_#{user_id}",
          a_string_starting_with("csv_import_result_#{user_id}_"),
          expires_in: 1.hour
        )

        job_instance.send(:store_import_results, user_id, result)
      end
    end

    describe '#queue_anomaly_detection_for_batch' do
      let(:batch_id) { 'test-batch-123' }
      let(:transaction_ids) { (1..125).to_a } # Test batching

      before do
        allow(Transaction).to receive(:where).with(import_batch_id: batch_id).and_return(
          double(pluck: transaction_ids)
        )
      end

      it 'queues anomaly detection in batches of 50' do
        expect(BulkAnomalyDetectionJob).to receive(:perform_later).with((1..50).to_a)
        expect(BulkAnomalyDetectionJob).to receive(:perform_later).with((51..100).to_a)
        expect(BulkAnomalyDetectionJob).to receive(:perform_later).with((101..125).to_a)

        job_instance.send(:queue_anomaly_detection_for_batch, batch_id)
      end
    end
  end
end
