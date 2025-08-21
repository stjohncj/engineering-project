class CsvImportJob < ApplicationJob
  queue_as :high_priority

  retry_on StandardError, wait: 5.seconds, attempts: 2

  def perform(file_path, user_id = nil, import_options = {})
    # Validate file exists
    unless File.exist?(file_path)
      Rails.logger.error "CsvImportJob: File not found at #{file_path}"
      return
    end

    begin
      # Create a file object for the service
      file = File.open(file_path, "r")

      # Run the import service
      result = CsvImportService.new(file).import

      # Log the results
      Rails.logger.info "CsvImportJob completed: #{result[:imported]} imported, #{result[:failed]} failed"

      # Store results for later retrieval if user_id provided
      if user_id
        store_import_results(user_id, result)
      end

      # Queue anomaly detection for imported transactions if enabled
      if import_options[:run_anomaly_detection] && result[:batch_id]
        queue_anomaly_detection_for_batch(result[:batch_id])
      end

    rescue => e
      Rails.logger.error "CsvImportJob failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Store error result if user_id provided
      if user_id
        store_import_results(user_id, {
          imported: 0,
          failed: 0,
          errors: [ "Import failed: #{e.message}" ],
          batch_id: nil,
          status: "failed"
        })
      end

      raise e
    ensure
      # Clean up the temporary file
      File.delete(file_path) if File.exist?(file_path)
      file&.close
    end
  end

  private

  def store_import_results(user_id, result)
    # Store import results in cache for user to retrieve
    cache_key = "csv_import_result_#{user_id}_#{Time.current.to_i}"
    Rails.cache.write(cache_key, result.merge(status: "completed"), expires_in: 1.hour)

    # Also store a reference to the latest result
    Rails.cache.write("csv_import_latest_#{user_id}", cache_key, expires_in: 1.hour)
  end

  def queue_anomaly_detection_for_batch(batch_id)
    # Queue anomaly detection jobs for all transactions in this batch
    transaction_ids = Transaction.where(import_batch_id: batch_id).pluck(:id)

    transaction_ids.each_slice(50) do |id_batch|
      BulkAnomalyDetectionJob.perform_later(id_batch)
    end
  end
end
