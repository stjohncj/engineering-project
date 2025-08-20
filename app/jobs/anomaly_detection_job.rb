class AnomalyDetectionJob < ApplicationJob
  queue_as :default
  
  # Retry failed jobs up to 3 times with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(transaction_id)
    transaction = Transaction.find(transaction_id)
    AnomalyDetectionService.new(transaction).detect_and_flag
    
    # Invalidate relevant caches after anomaly detection
    invalidate_anomaly_caches
    
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "AnomalyDetectionJob: Transaction #{transaction_id} not found"
    # Don't retry for missing records
  rescue => e
    Rails.logger.error "AnomalyDetectionJob failed for transaction #{transaction_id}: #{e.message}"
    raise e # Will trigger retry logic
  end
  
  private
  
  def invalidate_anomaly_caches
    Rails.cache.delete("active_anomalies")
    Rails.cache.delete("unresolved_anomalies_count")
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete_matched("anomaly_detections_index_*")
  end
end