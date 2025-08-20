class Transaction < ApplicationRecord
  belongs_to :category, optional: true
  has_many :anomaly_detections, foreign_key: :transaction_record_id, dependent: :destroy
  
  enum :status, { pending: 0, approved: 1, flagged: 2, rejected: 3 }
  
  validates :amount, presence: true, numericality: true
  validates :transaction_date, presence: true
  validates :description, length: { maximum: 500 }
  
  # Optimized scopes using indexed columns
  scope :uncategorized, -> { where(category_id: nil) }
  scope :with_anomalies, -> { joins(:anomaly_detections).distinct }
  scope :by_amount_range, ->(min, max) { where(amount: min..max) }
  scope :by_date_range, ->(start_date, end_date) { where(transaction_date: start_date..end_date) }
  scope :recent, -> { order(transaction_date: :desc, created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_category, ->(category_id) { where(category_id: category_id) }
  
  # Performance optimized scopes for analytics
  scope :for_month, ->(date) { where(transaction_date: date.beginning_of_month..date.end_of_month) }
  scope :for_year, ->(year) { where(transaction_date: Date.new(year).beginning_of_year..Date.new(year).end_of_year) }
  scope :large_amounts, ->(threshold = 1000) { where('amount > ?', threshold) }
  
  # Efficient counter cache helpers
  scope :count_by_status, -> { group(:status).count }
  scope :sum_by_category, -> { joins(:category).group('categories.name').sum(:amount) }
  
  before_save :generate_duplicate_hash
  
  def has_anomalies?
    anomaly_detections.unresolved.exists?
  end
  
  def flagged_anomalies
    anomaly_detections.unresolved
  end
  
  # Efficient class methods for large dataset operations
  def self.bulk_update_category(transaction_ids, category_id)
    where(id: transaction_ids).update_all(category_id: category_id, updated_at: Time.current)
  end
  
  def self.bulk_update_status(transaction_ids, status)
    where(id: transaction_ids).update_all(status: status, updated_at: Time.current)
  end
  
  def self.monthly_summary(year = Date.current.year)
    # Use raw SQL for maximum performance on large datasets
    query = <<-SQL
      SELECT 
        DATE_TRUNC('month', transaction_date) as month,
        COUNT(*) as transaction_count,
        SUM(amount) as total_amount,
        AVG(amount) as average_amount,
        status
      FROM transactions 
      WHERE EXTRACT(year FROM transaction_date) = ?
      GROUP BY DATE_TRUNC('month', transaction_date), status
      ORDER BY month DESC
    SQL
    
    connection.exec_query(query, 'monthly_summary', [year])
  end
  
  def self.category_analytics
    # Efficient category statistics using single query
    joins(:category)
      .select('categories.name, categories.id, COUNT(*) as transaction_count, SUM(amount) as total_amount, AVG(amount) as avg_amount')
      .group('categories.id, categories.name')
      .order('total_amount DESC')
  end
  
  def self.find_duplicates
    # Find potential duplicates efficiently using the duplicate_hash index
    select('duplicate_hash, COUNT(*) as count, ARRAY_AGG(id) as transaction_ids')
      .where.not(duplicate_hash: nil)
      .group(:duplicate_hash)
      .having('COUNT(*) > 1')
  end
  
  private
  
  def generate_duplicate_hash
    self.duplicate_hash = Digest::SHA256.hexdigest(
      "#{amount}_#{transaction_date}_#{description&.downcase&.strip}"
    )
  end
end
