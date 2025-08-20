class Transaction < ApplicationRecord
  belongs_to :category, optional: true
  has_many :anomaly_detections, foreign_key: :transaction_record_id, dependent: :destroy
  
  enum :status, { pending: 0, approved: 1, flagged: 2, rejected: 3 }
  
  validates :amount, presence: true, numericality: true
  validates :transaction_date, presence: true
  validates :description, length: { maximum: 500 }
  
  scope :uncategorized, -> { where(category: nil) }
  scope :with_anomalies, -> { joins(:anomaly_detections).distinct }
  scope :by_amount_range, ->(min, max) { where(amount: min..max) }
  scope :by_date_range, ->(start_date, end_date) { where(transaction_date: start_date..end_date) }
  
  before_save :generate_duplicate_hash
  
  def has_anomalies?
    anomaly_detections.unresolved.exists?
  end
  
  def flagged_anomalies
    anomaly_detections.unresolved
  end
  
  private
  
  def generate_duplicate_hash
    self.duplicate_hash = Digest::SHA256.hexdigest(
      "#{amount}_#{transaction_date}_#{description&.downcase&.strip}"
    )
  end
end
