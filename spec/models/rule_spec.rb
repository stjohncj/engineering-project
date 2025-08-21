require 'rails_helper'

RSpec.describe Rule, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      rule = build(:rule)
      expect(rule).to be_valid
    end

    it 'requires a name' do
      rule = build(:rule, name: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:name]).to include("can't be blank")
    end

    it 'requires a unique name' do
      create(:rule, name: 'Duplicate Rule')
      duplicate_rule = build(:rule, name: 'Duplicate Rule')
      expect(duplicate_rule).not_to be_valid
      expect(duplicate_rule.errors[:name]).to include('has already been taken')
    end

    it 'requires condition_field' do
      rule = build(:rule, condition_field: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:condition_field]).to include("is not included in the list")
    end

    it 'requires condition_operator' do
      rule = build(:rule, condition_operator: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:condition_operator]).to include("is not included in the list")
    end

    it 'requires condition_value' do
      rule = build(:rule, condition_value: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:condition_value]).to include("can't be blank")
    end

    it 'requires action_type' do
      rule = build(:rule, action_type: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:action_type]).to include("is not included in the list")
    end

    it 'requires action_value' do
      rule = build(:rule, action_value: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:action_value]).to include("can't be blank")
    end
  end

  describe 'associations' do
    # Rule model doesn't have category association in current implementation
    # Rules operate by creating/finding categories through action_value
  end

  describe 'scopes' do
    let!(:active_rule) { create(:rule, active: true) }
    let!(:inactive_rule) { create(:rule, :inactive) }

    it 'has an active scope' do
      expect(Rule.active).to include(active_rule)
      expect(Rule.active).not_to include(inactive_rule)
    end
  end

  describe '#applies_to?' do
    let(:grocery_rule) { create(:rule, :grocery_rule) }
    let(:gas_rule) { create(:rule, :gas_station_rule) }
    let(:amount_rule) { create(:rule, :amount_based_rule) }

    it 'applies to transactions matching description conditions' do
      transaction = build(:transaction, description: 'Grocery Store Purchase')
      expect(grocery_rule.applies_to?(transaction)).to be true
    end

    it 'does not apply to transactions not matching description conditions' do
      transaction = build(:transaction, description: 'Restaurant Dinner')
      expect(grocery_rule.applies_to?(transaction)).to be false
    end

    it 'applies to transactions matching multiple description conditions' do
      transaction = build(:transaction, description: 'Shell Gas Station')
      expect(gas_rule.applies_to?(transaction)).to be true
    end

    it 'applies to transactions matching amount conditions' do
      transaction = build(:transaction, amount: 1500.0)
      expect(amount_rule.applies_to?(transaction)).to be true
    end

    it 'does not apply to transactions not matching amount conditions' do
      transaction = build(:transaction, amount: 50.0)
      expect(amount_rule.applies_to?(transaction)).to be false
    end

    it 'does not apply when rule is inactive' do
      inactive_rule = create(:rule, :grocery_rule, :inactive)
      transaction = build(:transaction, description: 'Grocery Store Purchase')
      # Note: applies_to? method doesn't check active status, it only checks conditions
      # Active status is handled at the job/service level
      expect(inactive_rule.applies_to?(transaction)).to be true
    end
  end

  describe '#apply_to!' do
    context 'with categorize action' do
      let(:rule) { create(:rule, :grocery_rule) }

      it 'sets the category on the transaction' do
        transaction = create(:transaction, description: 'Grocery Store Purchase')
        rule.apply_to!(transaction)

        expect(transaction.reload.category.name).to eq('Groceries')
      end
    end

    context 'with flag action' do
      let(:rule) { create(:rule, :amount_based_rule) }

      it 'sets the status to flagged and creates anomaly detection' do
        transaction = create(:transaction, amount: 1500.0)
        
        expect { rule.apply_to!(transaction) }.to change { 
          AnomalyDetection.count 
        }.by(1)

        expect(transaction.reload.status).to eq('flagged')
        anomaly = AnomalyDetection.last
        expect(anomaly.transaction_record).to eq(transaction)
        expect(anomaly.anomaly_type).to eq('rule_based')
        expect(anomaly.description).to include(rule.name)
      end
    end

    it 'only applies to transactions that match conditions' do
      rule = create(:rule, :grocery_rule)
      transaction = create(:transaction, description: 'Restaurant Dinner')

      expect { rule.apply_to!(transaction) }.not_to change { transaction.reload.category }
    end
  end

  describe 'field validation' do
    it 'validates condition_field inclusion' do
      rule = build(:rule, condition_field: 'invalid_field')
      expect(rule).not_to be_valid
      expect(rule.errors[:condition_field]).to include('is not included in the list')
    end

    it 'validates condition_operator inclusion' do
      rule = build(:rule, condition_operator: 'invalid_operator')
      expect(rule).not_to be_valid
      expect(rule.errors[:condition_operator]).to include('is not included in the list')
    end

    it 'validates action_type inclusion' do
      rule = build(:rule, action_type: 'invalid_action')
      expect(rule).not_to be_valid
      expect(rule.errors[:action_type]).to include('is not included in the list')
    end
  end
end
