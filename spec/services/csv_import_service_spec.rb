require 'rails_helper'

RSpec.describe CsvImportService do
  include ActiveJob::TestHelper

  let(:valid_csv_content) do
    <<~CSV
      amount,description,date,category
      100.50,Grocery Store Purchase,2025-08-19,Groceries
      -85.75,Electric Bill,2025-08-20,Utilities
      250.00,Salary Deposit,2025-08-21,Income
      -45.20,Restaurant Dinner,2025-08-22,Dining
    CSV
  end

  let(:csv_file) do
    file = Tempfile.new(['test', '.csv'])
    file.write(valid_csv_content)
    file.rewind
    file
  end

  let(:service) { described_class.new(csv_file) }

  after do
    csv_file.close!
  end

  before do
    # Clear any existing jobs
    clear_enqueued_jobs
  end

  describe '#import' do
    context 'with valid CSV data' do
      it 'imports all valid transactions using batch processing' do
        result = service.import
        
        expect(result[:imported]).to eq(4)
        expect(result[:failed]).to eq(0)
        expect(result[:errors]).to be_empty
        expect(result[:batch_id]).to be_present
      end

      it 'creates transactions with correct attributes' do
        service.import
        
        transaction = Transaction.find_by(description: 'Grocery Store Purchase')
        expect(transaction).to be_present
        expect(transaction.amount).to eq(100.50)
        expect(transaction.transaction_date).to eq(Date.parse('2025-08-19'))
        expect(transaction.status).to eq('pending')
        expect(transaction.import_batch_id).to be_present
      end

      it 'creates or finds categories during processing' do
        expect { service.import }.to change(Category, :count).by(4)
        
        groceries = Category.find_by(name: 'Groceries')
        expect(groceries).to be_present
        
        transaction = Transaction.find_by(description: 'Grocery Store Purchase')
        expect(transaction.category).to eq(groceries)
      end

      it 'processes transactions in batches' do
        # Mock the batch size to be smaller for testing
        stub_const('CsvImportService::BATCH_SIZE', 2)
        
        expect(service).to receive(:process_batch).at_least(2).times.and_call_original
        
        service.import
      end

      it 'uses bulk insert for better performance' do
        expect(Transaction).to receive(:insert_all).at_least(:once).and_call_original
        
        service.import
      end

      it 'queues background jobs for post-processing' do
        service.import

        expect(BulkRuleApplicationJob).to have_been_enqueued
        expect(BulkAnomalyDetectionJob).to have_been_enqueued
      end

      it 'invalidates caches after import' do
        expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
        expect(Rails.cache).to receive(:delete).with("recent_transactions")
        expect(Rails.cache).to receive(:delete_matched).with("transactions_index_*")

        service.import
      end
    end

    context 'with invalid CSV data' do
      let(:invalid_csv_content) do
        <<~CSV
          amount,description,date,category
          invalid-amount,Bad Transaction,2025-08-19,Test
          100.50,Missing Date,,Test
          ,Empty Amount,2025-08-20,Test
        CSV
      end

      let(:invalid_csv_file) do
        file = Tempfile.new(['invalid', '.csv'])
        file.write(invalid_csv_content)
        file.rewind
        file
      end

      let(:invalid_service) { described_class.new(invalid_csv_file) }

      after { invalid_csv_file.close! }

      it 'handles parsing errors gracefully' do
        result = invalid_service.import
        
        expect(result[:imported]).to eq(0)
        expect(result[:failed]).to eq(3)
        expect(result[:errors]).to be_an(Array)
        expect(result[:errors].length).to eq(3)
      end

      it 'continues processing valid rows when some fail' do
        mixed_csv = <<~CSV
          amount,description,date,category
          100.50,Valid Transaction,2025-08-19,Test
          invalid,Invalid Transaction,2025-08-20,Test
          200.00,Another Valid,2025-08-21,Test
        CSV

        file = Tempfile.new(['mixed', '.csv'])
        file.write(mixed_csv)
        file.rewind
        mixed_service = described_class.new(file)

        result = mixed_service.import

        expect(result[:imported]).to eq(2)
        expect(result[:failed]).to eq(1)

        file.close!
      end
    end

    context 'with duplicate transactions' do
      let!(:existing_transaction) do
        create(:transaction,
               description: 'Grocery Store Purchase',
               amount: 100.50,
               transaction_date: Date.parse('2025-08-19'))
      end

      it 'detects and skips duplicates based on hash' do
        result = service.import
        
        # Should skip the duplicate grocery transaction
        expect(result[:imported]).to eq(3)
        expect(result[:failed]).to eq(1)
        expect(result[:errors]).to include(a_string_matching(/Duplicate transaction detected/))
      end

      it 'generates consistent duplicate hashes' do
        # Test that the same transaction data generates the same hash
        service_instance = service
        
        data1 = { amount: 100.50, transaction_date: Date.parse('2025-08-19'), description: 'Test' }
        data2 = { amount: 100.50, transaction_date: Date.parse('2025-08-19'), description: 'Test' }
        
        hash1 = service_instance.send(:generate_duplicate_hash, data1)
        hash2 = service_instance.send(:generate_duplicate_hash, data2)
        
        expect(hash1).to eq(hash2)
      end
    end

    context 'with large CSV file' do
      it 'processes large files in batches efficiently' do
        # Create a large CSV content
        large_csv = "amount,description,date,category\n"
        1500.times do |i|
          large_csv += "#{100 + i},Transaction #{i},2025-08-#{19 + (i % 10)},Category#{i % 5}\n"
        end

        large_file = Tempfile.new(['large', '.csv'])
        large_file.write(large_csv)
        large_file.rewind
        large_service = described_class.new(large_file)

        # Should process in multiple batches
        expect(large_service).to receive(:process_batch).at_least(2).times.and_call_original

        result = large_service.import

        expect(result[:imported]).to eq(1500)
        expect(result[:batch_id]).to be_present

        large_file.close!
      end
    end

    context 'when batch insert fails' do
      before do
        allow(Transaction).to receive(:insert_all).and_raise(StandardError, 'Database error')
      end

      it 'falls back to individual processing' do
        expect(service).to receive(:process_batch_individually).and_call_original
        expect(Rails.logger).to receive(:warn).with(/Batch insert failed/)

        result = service.import

        # Should still process transactions individually
        expect(result[:imported]).to eq(4)
      end
    end

    context 'post-processing jobs' do
      it 'queues rule application jobs with transaction IDs' do
        result = service.import

        imported_ids = Transaction.where(import_batch_id: result[:batch_id]).pluck(:id)
        expect(BulkRuleApplicationJob).to have_been_enqueued.with(imported_ids)
      end

      it 'queues anomaly detection in smaller batches' do
        # Create a scenario with 125 transactions to test batching
        large_csv = "amount,description,date,category\n"
        125.times do |i|
          large_csv += "#{100 + i},Transaction #{i},2025-08-19,Test\n"
        end

        large_file = Tempfile.new(['batch_test', '.csv'])
        large_file.write(large_csv)
        large_file.rewind
        large_service = described_class.new(large_file)

        large_service.import

        # Should queue 3 jobs: 50 + 50 + 25
        expect(BulkAnomalyDetectionJob).to have_been_enqueued.exactly(3).times

        large_file.close!
      end
    end
  end

  describe 'private methods' do
    let(:service_instance) { service }

    describe '#normalize_row_data' do
      it 'normalizes row data correctly' do
        row = {
          amount: '$100.50',
          description: '  Test Transaction  ',
          date: '2025-08-19',
          category: 'Test Category'
        }

        result = service_instance.send(:normalize_row_data, row)

        expect(result[:amount]).to eq(100.50)
        expect(result[:description]).to eq('Test Transaction')
        expect(result[:transaction_date]).to eq(Date.parse('2025-08-19'))
        expect(result[:category_id]).to be_present
      end
    end

    describe '#parse_amount' do
      it 'handles various amount formats' do
        expect(service_instance.send(:parse_amount, '100.50')).to eq(100.50)
        expect(service_instance.send(:parse_amount, '$100.50')).to eq(100.50)
        expect(service_instance.send(:parse_amount, '1,000.50')).to eq(1000.50)
        expect(service_instance.send(:parse_amount, '-50.25')).to eq(-50.25)
      end

      it 'raises error for invalid amounts' do
        expect { service_instance.send(:parse_amount, 'invalid') }.to raise_error(/Invalid amount format/)
      end
    end

    describe '#parse_date' do
      it 'handles various date formats' do
        expect(service_instance.send(:parse_date, '2025-08-19')).to eq(Date.parse('2025-08-19'))
        expect(service_instance.send(:parse_date, '08/19/2025')).to eq(Date.parse('2025-08-19'))
        expect(service_instance.send(:parse_date, '19/08/2025')).to eq(Date.parse('2025-08-19'))
      end

      it 'raises error for invalid dates' do
        expect { service_instance.send(:parse_date, 'invalid-date') }.to raise_error(/Invalid date format/)
      end
    end

    describe '#find_or_create_category' do
      it 'creates new categories' do
        expect { service_instance.send(:find_or_create_category, 'New Category') }
          .to change(Category, :count).by(1)
      end

      it 'finds existing categories' do
        existing_category = create(:category, name: 'Existing')
        
        result = service_instance.send(:find_or_create_category, 'Existing')
        expect(result).to eq(existing_category)
      end

      it 'handles blank category names' do
        result = service_instance.send(:find_or_create_category, '')
        expect(result).to be_nil
      end
    end
  end
end