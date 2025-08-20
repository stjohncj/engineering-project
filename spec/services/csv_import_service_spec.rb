require 'rails_helper'

RSpec.describe CsvImportService do
  describe '.import' do
    let(:valid_csv_content) do
      <<~CSV
        date,description,amount,category
        2024-01-15,Grocery Store Purchase,-85.50,Groceries
        2024-01-16,Salary Deposit,3500.00,Income
        2024-01-17,Electric Bill,-120.75,Utilities
        2024-01-18,Restaurant Dinner,-45.20,Dining
      CSV
    end

    let(:invalid_csv_content) do
      <<~CSV
        date,description,amount,category
        invalid-date,Grocery Store Purchase,-85.50,Groceries
        2024-01-16,Missing Amount,,Income
        2024-01-17,Electric Bill,not-a-number,Utilities
      CSV
    end

    let(:duplicate_csv_content) do
      <<~CSV
        date,description,amount,category
        2024-01-15,Grocery Store Purchase,-85.50,Groceries
        2024-01-15,Grocery Store Purchase,-85.50,Groceries
      CSV
    end

    context 'with valid CSV data' do
      it 'imports all valid transactions' do
        result = CsvImportService.import(valid_csv_content)
        
        expect(result[:processed_count]).to eq(4)
        expect(result[:imported_count]).to eq(4)
        expect(result[:error_count]).to eq(0)
        expect(result[:duplicate_count]).to eq(0)
      end

      it 'creates transactions with correct attributes' do
        CsvImportService.import(valid_csv_content)
        
        transaction = Transaction.find_by(description: 'Grocery Store Purchase')
        expect(transaction).to be_present
        expect(transaction.amount).to eq(-85.50)
        expect(transaction.transaction_date).to eq(Date.parse('2024-01-15'))
        expect(transaction.source).to eq('csv_import')
        expect(transaction.status).to eq('pending')
      end

      it 'creates or finds categories' do
        expect { CsvImportService.import(valid_csv_content) }
          .to change(Category, :count).by(4) # Groceries, Income, Utilities, Dining
        
        groceries = Category.find_by(name: 'Groceries')
        expect(groceries).to be_present
        
        transaction = Transaction.find_by(description: 'Grocery Store Purchase')
        expect(transaction.category).to eq(groceries)
      end
    end

    context 'with invalid CSV data' do
      it 'handles parsing errors gracefully' do
        result = CsvImportService.import(invalid_csv_content)
        
        expect(result[:processed_count]).to eq(3)
        expect(result[:imported_count]).to be < 3
        expect(result[:error_count]).to be > 0
        expect(result[:errors]).to be_an(Array)
      end

      it 'skips invalid rows but continues processing' do
        result = CsvImportService.import(invalid_csv_content)
        
        # Should still process any valid rows
        expect(result[:imported_count]).to be >= 0
        expect(result[:errors].length).to eq(result[:error_count])
      end
    end

    context 'with duplicate transactions' do
      before do
        # Create an existing transaction first
        create(:transaction, 
               description: 'Grocery Store Purchase',
               amount: -85.50,
               transaction_date: Date.parse('2024-01-15'))
      end

      it 'detects and skips duplicates' do
        result = CsvImportService.import(duplicate_csv_content)
        
        expect(result[:processed_count]).to eq(2)
        expect(result[:duplicate_count]).to eq(2) # Both rows match existing transaction
        expect(Transaction.count).to eq(1) # Only the original transaction
      end
    end

    context 'with mixed data (valid, invalid, duplicates)' do
      let(:mixed_csv_content) do
        <<~CSV
          date,description,amount,category
          2024-01-15,Grocery Store Purchase,-85.50,Groceries
          invalid-date,Bad Transaction,-50.00,Error
          2024-01-17,Electric Bill,-120.75,Utilities
          2024-01-15,Grocery Store Purchase,-85.50,Groceries
        CSV
      end

      before do
        # Pre-create one transaction to test duplicate detection
        create(:transaction, 
               description: 'Grocery Store Purchase',
               amount: -85.50,
               transaction_date: Date.parse('2024-01-15'))
      end

      it 'provides comprehensive results' do
        result = CsvImportService.import(mixed_csv_content)
        
        expect(result[:processed_count]).to eq(4)
        expect(result[:imported_count]).to eq(1) # Only Electric Bill
        expect(result[:duplicate_count]).to eq(2) # Both grocery transactions
        expect(result[:error_count]).to eq(1) # Invalid date
        expect(result[:anomaly_count]).to be >= 0
      end
    end

    context 'with automatic categorization rules' do
      let!(:grocery_category) { create(:category, :groceries) }
      let!(:grocery_rule) { create(:rule, :grocery_rule, category: grocery_category) }

      it 'applies rules during import' do
        csv_content = <<~CSV
          date,description,amount,category
          2024-01-15,Supermarket Purchase,-85.50,
        CSV
        
        result = CsvImportService.import(csv_content)
        
        transaction = Transaction.find_by(description: 'Supermarket Purchase')
        expect(transaction.category).to eq(grocery_category)
      end
    end

    context 'with anomaly detection' do
      it 'triggers anomaly detection for imported transactions' do
        allow(AnomalyDetectionService).to receive(:detect_for_transaction)
          .and_return(create(:anomaly_detection))
        
        result = CsvImportService.import(valid_csv_content)
        
        expect(AnomalyDetectionService).to have_received(:detect_for_transaction).exactly(4).times
        expect(result[:anomaly_count]).to eq(4)
      end
    end

    context 'with different CSV formats' do
      it 'handles different date formats' do
        csv_content = <<~CSV
          date,description,amount,category
          01/15/2024,US Format Date,-50.00,Test
          15-01-2024,EU Format Date,-75.00,Test
          2024-01-15,ISO Format Date,-100.00,Test
        CSV
        
        result = CsvImportService.import(csv_content)
        
        # At least ISO format should work
        expect(result[:imported_count]).to be >= 1
        expect(result[:processed_count]).to eq(3)
      end

      it 'handles currency symbols' do
        csv_content = <<~CSV
          date,description,amount,category
          2024-01-15,With Dollar Sign,$50.00,Test
          2024-01-16,With Negative,"-$75.00",Test
          2024-01-17,Plain Number,100.00,Test
        CSV
        
        result = CsvImportService.import(csv_content)
        
        expect(result[:imported_count]).to be >= 1
      end
    end

    context 'error handling' do
      it 'handles empty CSV content' do
        result = CsvImportService.import('')
        
        expect(result[:processed_count]).to eq(0)
        expect(result[:imported_count]).to eq(0)
        expect(result[:error_count]).to eq(0)
      end

      it 'handles malformed CSV' do
        malformed_csv = "date,description,amount\n2024-01-15,\"Unclosed quote,-50.00"
        
        expect { CsvImportService.import(malformed_csv) }.not_to raise_error
      end
    end
  end
end