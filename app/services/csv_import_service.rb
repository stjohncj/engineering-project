require 'csv'

class CsvImportService
  def initialize(file)
    @file = file
    @imported = 0
    @failed = 0
    @errors = []
    @batch_id = SecureRandom.uuid
  end
  
  def import
    CSV.foreach(@file.path, headers: true, header_converters: :symbol) do |row|
      begin
        process_row(row)
      rescue => e
        @failed += 1
        @errors << "Row #{$.}: #{e.message}"
      end
    end
    
    {
      imported: @imported,
      failed: @failed,
      errors: @errors,
      batch_id: @batch_id
    }
  end
  
  private
  
  def process_row(row)
    # Handle different CSV formats
    transaction_data = normalize_row_data(row)
    
    # Validate required fields
    validate_row_data(transaction_data)
    
    # Check for duplicates
    if duplicate_exists?(transaction_data)
      @failed += 1
      @errors << "Row #{$.}: Duplicate transaction detected"
      return
    end
    
    # Create transaction
    transaction = Transaction.new(transaction_data)
    transaction.import_batch_id = @batch_id
    
    if transaction.save
      @imported += 1
      
      # Apply rules and check for anomalies
      apply_post_processing(transaction)
    else
      @failed += 1
      @errors << "Row #{$.}: #{transaction.errors.full_messages.join(', ')}"
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
    cleaned = amount_str.to_s.gsub(/[$,]/, '')
    Float(cleaned)
  rescue ArgumentError
    raise "Invalid amount format: #{amount_str}"
  end
  
  def parse_date(date_str)
    return nil if date_str.blank?
    
    # Try different date formats
    formats = ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']
    
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
  
  def duplicate_exists?(data)
    hash = Digest::SHA256.hexdigest(
      "#{data[:amount]}_#{data[:transaction_date]}_#{data[:description]&.downcase&.strip}"
    )
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
end