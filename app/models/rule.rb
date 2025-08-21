class Rule < ApplicationRecord
  validates :name, presence: true
  validates :condition_field, inclusion: { in: %w[description amount transaction_date] }
  validates :condition_operator, inclusion: { in: %w[contains equals greater_than less_than] }
  validates :condition_value, presence: true
  validates :action_type, inclusion: { in: %w[categorize flag] }
  validates :action_value, presence: true

  scope :active, -> { where(active: true) }
  scope :categorization_rules, -> { where(action_type: "categorize") }
  scope :flagging_rules, -> { where(action_type: "flag") }

  def applies_to?(transaction)
    case condition_operator
    when "contains"
      transaction.send(condition_field)&.downcase&.include?(condition_value.downcase)
    when "equals"
      transaction.send(condition_field)&.to_s == condition_value
    when "greater_than"
      transaction.send(condition_field).to_f > condition_value.to_f
    when "less_than"
      transaction.send(condition_field).to_f < condition_value.to_f
    else
      false
    end
  end

  def apply_to!(transaction)
    return unless applies_to?(transaction)

    case action_type
    when "categorize"
      category = Category.find_or_create_by(name: action_value)
      transaction.update!(category: category)
    when "flag"
      transaction.update!(status: :flagged)
      AnomalyDetection.create!(
        transaction_record: transaction,
        anomaly_type: "rule_based",
        severity: 2,
        description: "Flagged by rule: #{name}",
        resolved: false
      )
    end
  end
end
