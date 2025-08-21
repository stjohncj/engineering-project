class BulkRuleApplicationJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(transaction_ids, rule_ids = nil)
    # Apply rules to multiple transactions efficiently
    transactions = Transaction.includes(:category).where(id: transaction_ids)
    rules = rule_ids ? Rule.active.where(id: rule_ids) : Rule.active

    processed_count = 0

    # Process in batches to avoid memory issues
    transactions.find_in_batches(batch_size: 100) do |batch|
      batch.each do |transaction|
        rules.each do |rule|
          begin
            rule.apply_to!(transaction)
            processed_count += 1
          rescue => e
            Rails.logger.error "Failed to apply rule #{rule.id} to transaction #{transaction.id}: #{e.message}"
          end
        end
      end
    end

    # Invalidate relevant caches
    invalidate_transaction_caches

    Rails.logger.info "BulkRuleApplicationJob: Applied rules to #{processed_count} transactions"

  rescue => e
    Rails.logger.error "BulkRuleApplicationJob failed: #{e.message}"
    raise e
  end

  private

  def invalidate_transaction_caches
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete("recent_transactions")
    Rails.cache.delete("category_breakdown")
    Rails.cache.delete_matched("transactions_index_*")
  end
end
