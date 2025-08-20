class AnomalyDetection < ApplicationRecord
  belongs_to :transaction_record, class_name: 'Transaction'
  
  validates :anomaly_type, presence: true, inclusion: { in: %w[unusual_amount potential_duplicate incomplete_metadata rule_based] }
  validates :severity, presence: true, inclusion: { in: 1..5 }
  validates :description, presence: true
  
  scope :unresolved, -> { where(resolved: false) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_type, ->(type) { where(anomaly_type: type) }
  
  def severity_label
    case severity
    when 1 then 'Low'
    when 2 then 'Medium'
    when 3 then 'High'
    when 4 then 'Critical'
    when 5 then 'Urgent'
    end
  end
  
  def resolve!
    update!(resolved: true)
  end
end
