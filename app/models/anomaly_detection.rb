class AnomalyDetection < ApplicationRecord
  belongs_to :transaction_record, class_name: "Transaction"

  # Alias for easier access in tests and API
  def transaction
    transaction_record
  end

  def transaction=(trans)
    self.transaction_record = trans
  end

  validates :anomaly_type, presence: true
  validates :severity, presence: true, inclusion: { in: 1..5 }
  validates :description, presence: true

  # Optimized scopes using indexed columns
  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_type, ->(type) { where(anomaly_type: type) }
  scope :high_priority, -> { where(severity: 4..5) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_priority, -> { order(severity: :desc, created_at: :desc) }

  # Performance optimized scopes for analytics
  scope :count_by_type, -> { group(:anomaly_type).count }
  scope :count_by_severity, -> { group(:severity).count }
  scope :count_unresolved_by_type, -> { unresolved.group(:anomaly_type).count }

  before_create :set_detected_at

  def severity_label
    case severity
    when 1 then "Low"
    when 2 then "Low-Medium"
    when 3 then "Medium"
    when 4 then "High"
    when 5 then "Critical"
    end
  end

  def resolve!
    return if resolved?

    update!(resolved: true, resolved_at: Time.current)
  end

  private

  def set_detected_at
    self.detected_at ||= Time.current
  end
end
