require 'rails_helper'

RSpec.describe Category, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      category = build(:category)
      expect(category).to be_valid
    end

    it 'requires a name' do
      category = build(:category, name: nil)
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include("can't be blank")
    end

    it 'requires a unique name' do
      create(:category, name: 'Groceries')
      duplicate_category = build(:category, name: 'Groceries')
      expect(duplicate_category).not_to be_valid
      expect(duplicate_category.errors[:name]).to include('has already been taken')
    end
  end

  describe 'associations' do
    it 'has many transactions' do
      association = described_class.reflect_on_association(:transactions)
      expect(association.macro).to eq(:has_many)
    end

    # Category doesn't have rules association in current implementation
    # Rules reference categories through action_value field

    it 'destroys dependent transactions when deleted' do
      category = create(:category)
      transaction = create(:transaction, category: category)

      expect { category.destroy }.to change(Transaction, :count).by(-1)
    end
  end

  describe '#to_s' do
    it 'returns the category name' do
      category = build(:category, name: 'Transportation')
      expect(category.to_s).to eq('Transportation')
    end
  end
end
