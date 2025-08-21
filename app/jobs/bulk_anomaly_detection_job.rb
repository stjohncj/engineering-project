class BulkAnomalyDetectionJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(transaction_ids)
    processed_count = 0
    failed_count = 0

    # Load transactions with necessary associations
    transactions = Transaction.includes(:category, :anomaly_detections)
                              .where(id: transaction_ids)

    transactions.each do |transaction|
      begin
        AnomalyDetectionService.new(transaction).detect_and_flag
        processed_count += 1
      rescue => e
        Rails.logger.error "Failed anomaly detection for transaction #{transaction.id}: #{e.message}"
        failed_count += 1
      end
    end

    # Invalidate relevant caches after bulk processing
    invalidate_anomaly_caches

    Rails.logger.info "BulkAnomalyDetectionJob: Processed #{processed_count} transactions, #{failed_count} failed"

  rescue => e
    Rails.logger.error "BulkAnomalyDetectionJob failed: #{e.message}"
    raise e
  end

  private

  def invalidate_anomaly_caches
    Rails.cache.delete("active_anomalies")
    Rails.cache.delete("unresolved_anomalies_count")
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete_matched("anomaly_detections_index_*")
  end
end
