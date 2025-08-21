require "csv"

class CsvImportService
  BATCH_SIZE = 1000 # Process 1000 records at a time for optimal performance

  def initialize(file)
    @file = file
    @imported = 0
    @failed = 0
    @errors = []
    @batch_id = SecureRandom.uuid
  end

  def import
    transactions_batch = []
    row_number = 0

    # Handle both file objects and file paths
    file_path = @file.respond_to?(:path) ? @file.path : @file

    CSV.foreach(file_path, headers: true, header_converters: :symbol) do |row|
      row_number += 1

      begin
        transaction_data = prepare_transaction_data(row, row_number)
        transactions_batch << transaction_data if transaction_data

        # Process batch when it reaches BATCH_SIZE
        if transactions_batch.size >= BATCH_SIZE
          process_batch(transactions_batch)
          transactions_batch.clear
        end

      rescue => e
        @failed += 1
        @errors << "Row #{row_number}: #{e.message}"
      end
    end

    # Process remaining transactions
    process_batch(transactions_batch) if transactions_batch.any?

    # Invalidate caches after bulk import
    invalidate_caches

    {
      imported: @imported,
      failed: @failed,
      errors: @errors,
      batch_id: @batch_id
    }
  end

  private

  def prepare_transaction_data(row, row_number)
    # Handle different CSV formats
    transaction_data = normalize_row_data(row)

    # Validate required fields
    validate_row_data(transaction_data)

    # Check for duplicates using efficient hash lookup
    duplicate_hash = generate_duplicate_hash(transaction_data)
    if duplicate_exists?(duplicate_hash)
      @failed += 1
      @errors << "Row #{row_number}: Duplicate transaction detected"
      return nil
    end

    # Prepare transaction data with batch metadata
    transaction_data.merge({
      import_batch_id: @batch_id,
      duplicate_hash: duplicate_hash,
      created_at: Time.current,
      updated_at: Time.current
    })
  end

  def process_batch(transactions_batch)
    return if transactions_batch.empty?

    # Use database transaction for consistency
    Transaction.transaction do
      # Bulk insert transactions for maximum performance
      result = Transaction.insert_all(transactions_batch, returning: [ :id ])
      transaction_ids = result.rows.flatten

      @imported += transaction_ids.size

      # Batch process rules and anomaly detection
      if transaction_ids.any?
        apply_batch_post_processing(transaction_ids)
      end
    end
  rescue => e
    # If batch fails, fall back to individual processing
    Rails.logger.warn "Batch insert failed: #{e.message}. Falling back to individual processing."
    process_batch_individually(transactions_batch)
  end

  def process_batch_individually(transactions_batch)
    transactions_batch.each_with_index do |transaction_data, index|
      begin
        transaction = Transaction.create!(transaction_data)
        apply_post_processing(transaction)
        @imported += 1
      rescue => e
        @failed += 1
        @errors << "Batch row #{index + 1}: #{e.message}"
      end
    end
  end

  def apply_batch_post_processing(transaction_ids)
    # Queue bulk rule application for background processing
    BulkRuleApplicationJob.perform_later(transaction_ids)

    # Queue bulk anomaly detection for background processing
    # Process in smaller batches to avoid overwhelming the queue
    transaction_ids.each_slice(50) do |batch_ids|
      BulkAnomalyDetectionJob.perform_later(batch_ids)
    end
  end

  def normalize_row_data(row)
    {
      amount: parse_amount(row[:amount]),
      description: clean_description(row[:description]),
      transaction_date: parse_date(row[:date] || row[:transaction_date]),
      category_id: find_or_create_category(row[:category])&.id
    }
  end

  def validate_row_data(data)
    raise "Amount is required" if data[:amount].blank?
    raise "Date is required" if data[:transaction_date].blank?
    raise "Description is required" if data[:description].blank?
  end

  def parse_amount(amount_str)
    return nil if amount_str.blank?

    # Remove currency symbols and commas
    cleaned = amount_str.to_s.gsub(/[$,]/, "")
    Float(cleaned)
  rescue ArgumentError
    raise "Invalid amount format: #{amount_str}"
  end

  def parse_date(date_str)
    return nil if date_str.blank?

    # Try different date formats
    formats = [ "%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d" ]

    formats.each do |format|
      begin
        return Date.strptime(date_str.to_s, format)
      rescue ArgumentError
        next
      end
    end

    # Try parsing as-is
    Date.parse(date_str.to_s)
  rescue ArgumentError
    raise "Invalid date format: #{date_str}"
  end

  def clean_description(description)
    return nil if description.blank?
    description.to_s.strip.truncate(500)
  end

  def find_or_create_category(category_name)
    return nil if category_name.blank?
    Category.find_or_create_by(name: category_name.to_s.strip)
  end

  def generate_duplicate_hash(data)
    Digest::SHA256.hexdigest(
      "#{data[:amount]}_#{data[:transaction_date]}_#{data[:description]&.downcase&.strip}"
    )
  end

  def duplicate_exists?(hash)
    # Use indexed lookup for fast duplicate checking
    Transaction.exists?(duplicate_hash: hash)
  end

  def apply_post_processing(transaction)
    # Apply categorization rules
    Rule.active.each do |rule|
      rule.apply_to!(transaction)
    end

    # Check for anomalies
    AnomalyDetectionService.new(transaction).detect_and_flag
  end

  def invalidate_caches
    # Clear all transaction-related caches after bulk import
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete("recent_transactions")
    Rails.cache.delete("active_anomalies")
    Rails.cache.delete("total_transactions_count")
    Rails.cache.delete("total_amount_sum")
    Rails.cache.delete("active_rules_count")
    Rails.cache.delete("unresolved_anomalies_count")
    Rails.cache.delete("categories_count")
    Rails.cache.delete("monthly_transaction_trends")
    Rails.cache.delete("category_breakdown")
    Rails.cache.delete_matched("transactions_index_*")
    Rails.cache.delete_matched("total_transactions_filtered_*")
  end
end
