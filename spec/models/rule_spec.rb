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

    it 'requires conditions' do
      rule = build(:rule, conditions: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include("can't be blank")
    end

    it 'requires actions' do
      rule = build(:rule, actions: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:actions]).to include("can't be blank")
    end
  end

  describe 'associations' do
    it 'belongs to category' do
      association = described_class.reflect_on_association(:category)
      expect(association.macro).to eq(:belongs_to)
    end
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
    let(:category) { create(:category, :groceries) }
    let(:grocery_rule) { create(:rule, :grocery_rule, category: category) }
    let(:gas_rule) { create(:rule, :gas_station_rule, category: category) }
    let(:amount_rule) { create(:rule, :amount_based_rule, category: category) }

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
      inactive_rule = create(:rule, :grocery_rule, :inactive, category: category)
      transaction = build(:transaction, description: 'Grocery Store Purchase')
      expect(inactive_rule.applies_to?(transaction)).to be false
    end
  end

  describe '#apply_to!' do
    let(:category) { create(:category, name: 'Groceries') }
    let(:transportation_category) { create(:category, name: 'Transportation') }
    
    context 'with set_category action' do
      let(:rule) do
        create(:rule, 
               category: category,
               conditions: { "description_contains" => ["grocery"] },
               actions: { "set_category" => "Transportation" })
      end

      it 'sets the category on the transaction' do
        transaction = create(:transaction, description: 'Grocery Store Purchase')
        rule.apply_to!(transaction)
        
        expect(transaction.reload.category).to eq(transportation_category)
      end
    end

    context 'with set_status action' do
      let(:rule) do
        create(:rule, 
               category: category,
               conditions: { "amount_greater_than" => 1000.0 },
               actions: { "set_status" => "flagged" })
      end

      it 'sets the status on the transaction' do
        transaction = create(:transaction, amount: 1500.0)
        rule.apply_to!(transaction)
        
        expect(transaction.reload.status).to eq('flagged')
      end
    end

    it 'only applies to transactions that match conditions' do
      rule = create(:rule, :grocery_rule, category: category)
      transaction = create(:transaction, description: 'Restaurant Dinner')
      
      expect { rule.apply_to!(transaction) }.not_to change { transaction.reload.category }
    end
  end

  describe 'JSON serialization' do
    it 'properly serializes and deserializes conditions' do
      conditions = { "description_contains" => ["grocery", "food"], "amount_less_than" => 100.0 }
      rule = create(:rule, conditions: conditions)
      
      expect(rule.reload.conditions).to eq(conditions)
    end

    it 'properly serializes and deserializes actions' do
      actions = { "set_category" => "Groceries", "set_status" => "approved" }
      rule = create(:rule, actions: actions)
      
      expect(rule.reload.actions).to eq(actions)
    end
  end
end