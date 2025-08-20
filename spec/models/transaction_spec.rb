require 'rails_helper'

RSpec.describe Transaction, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      transaction = build(:transaction)
      expect(transaction).to be_valid
    end

    it 'requires an amount' do
      transaction = build(:transaction, amount: nil)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include("can't be blank")
    end

    it 'requires amount to be numeric' do
      transaction = build(:transaction, amount: 'not_a_number')
      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include('is not a number')
    end

    it 'requires a transaction_date' do
      transaction = build(:transaction, transaction_date: nil)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:transaction_date]).to include("can't be blank")
    end

    it 'accepts positive amounts' do
      transaction = build(:transaction, :positive_amount)
      expect(transaction).to be_valid
    end

    it 'accepts negative amounts' do
      transaction = build(:transaction, :negative_amount)
      expect(transaction).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to category optionally' do
      association = described_class.reflect_on_association(:category)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be true
    end

    it 'has many anomaly_detections' do
      association = described_class.reflect_on_association(:anomaly_detections)
      expect(association.macro).to eq(:has_many)
    end

    it 'destroys dependent anomaly_detections when deleted' do
      transaction = create(:transaction)
      anomaly = create(:anomaly_detection, transaction: transaction)
      
      expect { transaction.destroy }.to change(AnomalyDetection, :count).by(-1)
    end
  end

  describe 'enums' do
    it 'defines status enum' do
      expect(Transaction.statuses.keys).to match_array(%w[pending approved flagged rejected])
    end

    it 'has pending status by default' do
      transaction = build(:transaction)
      expect(transaction.status).to eq('pending')
    end

    it 'can change status to approved' do
      transaction = create(:transaction)
      transaction.update(status: 'approved')
      expect(transaction.approved?).to be true
    end
  end

  describe 'scopes and methods' do
    let(:category) { create(:category, :groceries) }
    
    before do
      create(:transaction, :positive_amount, category: category, transaction_date: 1.week.ago)
      create(:transaction, :negative_amount, category: category, transaction_date: 2.weeks.ago)
      create(:transaction, :positive_amount, transaction_date: 3.weeks.ago) # no category
    end

    it 'can find transactions by category' do
      transactions = Transaction.joins(:category).where(categories: { name: 'Groceries' })
      expect(transactions.count).to eq(2)
    end

    it 'can find transactions without category' do
      transactions = Transaction.where(category: nil)
      expect(transactions.count).to eq(1)
    end
  end

  describe '#generate_duplicate_hash' do
    it 'generates a hash for duplicate detection' do
      transaction = create(:transaction, 
                          description: 'Test Transaction',
                          amount: 100.50,
                          transaction_date: Date.current)
      
      expect(transaction.duplicate_hash).to be_present
      expect(transaction.duplicate_hash.length).to eq(64) # SHA256 length
    end

    it 'generates same hash for similar transactions' do
      attrs = {
        description: 'Grocery Store',
        amount: 85.50,
        transaction_date: Date.current
      }
      
      transaction1 = create(:transaction, attrs)
      transaction2 = build(:transaction, attrs)
      transaction2.send(:generate_duplicate_hash)
      
      expect(transaction1.duplicate_hash).to eq(transaction2.duplicate_hash)
    end
  end

  describe 'callbacks' do
    it 'generates duplicate hash before save' do
      transaction = build(:transaction)
      expect(transaction.duplicate_hash).to be_nil
      
      transaction.save
      expect(transaction.duplicate_hash).to be_present
    end
  end
end