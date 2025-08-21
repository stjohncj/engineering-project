require 'rails_helper'

RSpec.describe AnomalyDetection, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      anomaly = build(:anomaly_detection)
      expect(anomaly).to be_valid
    end

    it 'requires anomaly_type' do
      anomaly = build(:anomaly_detection, anomaly_type: nil)
      expect(anomaly).not_to be_valid
      expect(anomaly.errors[:anomaly_type]).to include("can't be blank")
    end

    it 'requires description' do
      anomaly = build(:anomaly_detection, description: nil)
      expect(anomaly).not_to be_valid
      expect(anomaly.errors[:description]).to include("can't be blank")
    end

    it 'requires severity between 1 and 5' do
      anomaly = build(:anomaly_detection, severity: 0)
      expect(anomaly).not_to be_valid
      expect(anomaly.errors[:severity]).to include('must be greater than or equal to 1')

      anomaly = build(:anomaly_detection, severity: 6)
      expect(anomaly).not_to be_valid
      expect(anomaly.errors[:severity]).to include('must be less than or equal to 5')

      anomaly = build(:anomaly_detection, severity: 3)
      expect(anomaly).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to transaction' do
      association = described_class.reflect_on_association(:transaction)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:foreign_key]).to eq(:transaction_record_id)
    end
  end

  describe 'scopes' do
    let!(:resolved_anomaly) { create(:anomaly_detection, :resolved) }
    let!(:unresolved_anomaly) { create(:anomaly_detection, resolved: false) }

    it 'has an unresolved scope' do
      expect(AnomalyDetection.unresolved).to include(unresolved_anomaly)
      expect(AnomalyDetection.unresolved).not_to include(resolved_anomaly)
    end

    it 'has a resolved scope' do
      expect(AnomalyDetection.resolved).to include(resolved_anomaly)
      expect(AnomalyDetection.resolved).not_to include(unresolved_anomaly)
    end
  end

  describe 'severity ordering' do
    let!(:low_severity) { create(:anomaly_detection, :low_severity) }
    let!(:high_severity) { create(:anomaly_detection, :high_severity) }
    let!(:medium_severity) { create(:anomaly_detection, severity: 3) }

    it 'orders by severity descending' do
      ordered = AnomalyDetection.order(severity: :desc)
      expect(ordered.first).to eq(high_severity)
      expect(ordered.last).to eq(low_severity)
    end

    it 'can filter by minimum severity' do
      high_severity_anomalies = AnomalyDetection.where('severity >= ?', 4)
      expect(high_severity_anomalies).to include(high_severity)
      expect(high_severity_anomalies).not_to include(medium_severity)
      expect(high_severity_anomalies).not_to include(low_severity)
    end
  end

  describe '#severity_label' do
    it 'returns correct labels for different severities' do
      expect(build(:anomaly_detection, severity: 1).severity_label).to eq('Low')
      expect(build(:anomaly_detection, severity: 2).severity_label).to eq('Low-Medium')
      expect(build(:anomaly_detection, severity: 3).severity_label).to eq('Medium')
      expect(build(:anomaly_detection, severity: 4).severity_label).to eq('High')
      expect(build(:anomaly_detection, severity: 5).severity_label).to eq('Critical')
    end
  end

  describe '#resolve!' do
    it 'marks anomaly as resolved' do
      anomaly = create(:anomaly_detection, resolved: false)

      anomaly.resolve!

      expect(anomaly.reload.resolved).to be true
      expect(anomaly.resolved_at).to be_within(1.second).of(Time.current)
    end

    it 'does not change already resolved anomaly' do
      original_time = 1.hour.ago
      anomaly = create(:anomaly_detection, :resolved, resolved_at: original_time)

      anomaly.resolve!

      expect(anomaly.reload.resolved_at).to be_within(1.second).of(original_time)
    end
  end

  describe 'anomaly types' do
    it 'handles different anomaly types correctly' do
      unusual_amount = create(:anomaly_detection, anomaly_type: 'unusual_amount')
      potential_duplicate = create(:anomaly_detection, :potential_duplicate)
      incomplete_data = create(:anomaly_detection, :incomplete_data)

      expect(unusual_amount.anomaly_type).to eq('unusual_amount')
      expect(potential_duplicate.anomaly_type).to eq('potential_duplicate')
      expect(incomplete_data.anomaly_type).to eq('incomplete_data')
    end
  end

  describe 'metadata handling' do
    it 'properly stores and retrieves JSON metadata' do
      metadata = {
        "expected_range" => "10-100",
        "actual_amount" => "500",
        "confidence_score" => 0.85
      }

      anomaly = create(:anomaly_detection, metadata: metadata)

      expect(anomaly.reload.metadata).to eq(metadata)
    end

    it 'handles empty metadata' do
      anomaly = create(:anomaly_detection, metadata: {})
      expect(anomaly.reload.metadata).to eq({})
    end
  end

  describe 'timestamps' do
    it 'sets detected_at by default' do
      anomaly = create(:anomaly_detection)
      expect(anomaly.detected_at).to be_within(1.second).of(Time.current)
    end

    it 'allows custom detected_at time' do
      custom_time = 2.hours.ago
      anomaly = create(:anomaly_detection, detected_at: custom_time)
      expect(anomaly.detected_at).to be_within(1.second).of(custom_time)
    end
  end
end
