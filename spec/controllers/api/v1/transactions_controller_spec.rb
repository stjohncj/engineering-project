require 'rails_helper'

RSpec.describe Api::V1::TransactionsController, type: :controller do
  include ActiveJob::TestHelper

  before do
    # Clear cache before each test
    Rails.cache.clear
  end
  let(:valid_attributes) do
    {
      description: 'Test Transaction',
      amount: 100.50,
      transaction_date: Date.current
    }
  end

  let(:invalid_attributes) do
    {
      description: '',
      amount: nil,
      transaction_date: nil
    }
  end

  describe 'GET #index' do
    let!(:transactions) { create_list(:transaction, 3, :with_category) }

    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end

    it 'returns all transactions' do
      get :index
      json = JSON.parse(response.body)
      expect(json['transactions'].length).to eq(3)
    end

    it 'includes pagination metadata' do
      get :index
      json = JSON.parse(response.body)
      expect(json).to have_key('pagination')
      expect(json['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages', 'next_page', 'prev_page')
    end

    it 'handles unpermitted parameters gracefully' do
      # This test catches ActionController::UnfilteredParameters errors
      get :index, params: {
        malicious_param: 'hack_attempt',
        another_bad_param: { nested: 'data' },
        valid_param: 5
      }
      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json).to have_key('transactions')
      expect(json).to have_key('pagination')
    end

    it 'does not crash with complex parameter combinations' do
      # Test the exact scenario that caused our bug
      get :index, params: {
        page: 1,
        per_page: 10,
        category_id: 1,
        status: 'pending',
        search: 'test',
        format: 'json'
      }
      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json['pagination']['total_count']).to be >= 0
    end

    it 'caches the response for 2 minutes' do
      expect(Rails.cache).to receive(:fetch).with(
        a_string_starting_with("transactions_index_"),
        expires_in: 2.minutes
      ).and_call_original

      get :index
      expect(response.headers['Cache-Control']).to include('public')
    end

    it 'sets appropriate HTTP cache headers' do
      get :index
      expect(response.headers['Cache-Control']).to include('max-age=300')
      expect(response.headers['Vary']).to include('Accept', 'Authorization')
    end

    context 'with filters' do
      let!(:grocery_category) { create(:category, name: 'Groceries') }
      let!(:transport_category) { create(:category, name: 'Transportation') }
      let!(:grocery_transaction) { create(:transaction, category: grocery_category) }
      let!(:transport_transaction) { create(:transaction, category: transport_category) }

      it 'filters by category' do
        get :index, params: { category: 'Groceries' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['category']).to eq('Groceries')
      end

      it 'filters by status' do
        flagged_transaction = create(:transaction, status: 'flagged')
        get :index, params: { status: 'flagged' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['status']).to eq('flagged')
      end

      it 'filters by date range' do
        old_transaction = create(:transaction, transaction_date: 1.month.ago)
        recent_transaction = create(:transaction, transaction_date: Date.current)

        get :index, params: {
          start_date: 1.week.ago.to_date,
          end_date: Date.current
        }
        json = JSON.parse(response.body)

        dates = json['transactions'].map { |t| Date.parse(t['transaction_date']) }
        expect(dates.all? { |date| date >= 1.week.ago.to_date }).to be true
      end
    end

    context 'with pagination' do
      let!(:many_transactions) { create_list(:transaction, 25) }

      it 'paginates results correctly' do
        get :index, params: { per_page: 10 }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(10)
        expect(json['pagination']['total_count']).to eq(28) # 25 + 3 from earlier
        expect(json['pagination']['per_page']).to eq(10)
        expect(json['pagination']['total_pages']).to eq(3)
      end

      it 'returns specific page' do
        get :index, params: { page: 2, per_page: 10 }
        json = JSON.parse(response.body)
        expect(json['pagination']['current_page']).to eq(2)
        expect(json['pagination']['prev_page']).to eq(1)
        expect(json['pagination']['next_page']).to eq(3)
      end

      it 'ensures total_count is never zero when transactions exist' do
        # This test catches the bug we just fixed where total_count was 0
        get :index, params: { per_page: 5 }
        json = JSON.parse(response.body)
        expect(json['pagination']['total_count']).to be > 0
        expect(json['pagination']['total_count']).to eq(Transaction.count)
      end

      it 'calculates total_pages correctly based on total_count' do
        total_transactions = Transaction.count
        per_page = 7
        expected_pages = (total_transactions.to_f / per_page).ceil

        get :index, params: { per_page: per_page }
        json = JSON.parse(response.body)
        expect(json['pagination']['total_pages']).to eq(expected_pages)
      end

      it 'handles edge case with exact page boundary' do
        # Create exact multiple of page size to test boundary conditions
        Transaction.delete_all
        create_list(:transaction, 20) # Exactly 4 pages of 5

        get :index, params: { per_page: 5 }
        json = JSON.parse(response.body)
        expect(json['pagination']['total_count']).to eq(20)
        expect(json['pagination']['total_pages']).to eq(4)
        expect(json['pagination']['next_page']).to eq(2)
      end

      it 'handles last page correctly' do
        total_count = Transaction.count
        per_page = 10
        last_page = (total_count.to_f / per_page).ceil

        get :index, params: { page: last_page, per_page: per_page }
        json = JSON.parse(response.body)
        expect(json['pagination']['current_page']).to eq(last_page)
        expect(json['pagination']['next_page']).to be_nil
      end
    end
  end

  describe 'GET #show' do
    let!(:transaction) { create(:transaction, :with_category) }

    it 'returns a success response' do
      get :show, params: { id: transaction.to_param }
      expect(response).to be_successful
    end

    it 'returns the transaction' do
      get :show, params: { id: transaction.to_param }
      json = JSON.parse(response.body)
      expect(json['transaction']['id']).to eq(transaction.id)
    end

    it 'includes associated anomalies' do
      anomaly = create(:anomaly_detection, transaction: transaction)
      get :show, params: { id: transaction.to_param }
      json = JSON.parse(response.body)
      expect(json['transaction']['anomalies']).to be_present
    end

    it 'returns 404 for non-existent transaction' do
      get :show, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new Transaction' do
        expect {
          post :create, params: { transaction: valid_attributes }
        }.to change(Transaction, :count).by(1)
      end

      it 'returns a created response' do
        post :create, params: { transaction: valid_attributes }
        expect(response).to have_http_status(:created)
      end

      it 'returns the created transaction' do
        post :create, params: { transaction: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['transaction']['description']).to eq('Test Transaction')
      end

      it 'invalidates transaction caches' do
        expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
        expect(Rails.cache).to receive(:delete).with("recent_transactions")
        expect(Rails.cache).to receive(:delete_matched).with("transactions_index_*")

        post :create, params: { transaction: valid_attributes }
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new Transaction' do
        expect {
          post :create, params: { transaction: invalid_attributes }
        }.not_to change(Transaction, :count)
      end

      it 'returns an unprocessable entity response' do
        post :create, params: { transaction: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error messages' do
        post :create, params: { transaction: invalid_attributes }
        json = JSON.parse(response.body)
        expect(json).to have_key('errors')
      end
    end

    context 'with category assignment' do
      let(:category) { create(:category, name: 'Test Category') }

      it 'assigns category by name' do
        post :create, params: {
          transaction: valid_attributes.merge(category_name: 'Test Category')
        }
        json = JSON.parse(response.body)
        expect(json['transaction']['category']).to eq('Test Category')
      end
    end
  end

  describe 'PATCH #update' do
    let!(:transaction) { create(:transaction) }

    context 'with valid parameters' do
      let(:new_attributes) { { description: 'Updated Transaction' } }

      it 'updates the transaction' do
        patch :update, params: { id: transaction.to_param, transaction: new_attributes }
        transaction.reload
        expect(transaction.description).to eq('Updated Transaction')
      end

      it 'returns a success response' do
        patch :update, params: { id: transaction.to_param, transaction: new_attributes }
        expect(response).to be_successful
      end

      it 'invalidates transaction caches' do
        expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
        expect(Rails.cache).to receive(:delete).with("recent_transactions")
        expect(Rails.cache).to receive(:delete_matched).with("transactions_index_*")

        patch :update, params: { id: transaction.to_param, transaction: new_attributes }
      end
    end

    context 'with invalid parameters' do
      it 'returns an unprocessable entity response' do
        patch :update, params: { id: transaction.to_param, transaction: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:transaction) { create(:transaction) }

    it 'destroys the requested transaction' do
      expect {
        delete :destroy, params: { id: transaction.to_param }
      }.to change(Transaction, :count).by(-1)
    end

    it 'returns no content response' do
      delete :destroy, params: { id: transaction.to_param }
      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST #import_csv' do
    let(:csv_file) do
      file = Tempfile.new([ 'test', '.csv' ])
      file.write("amount,description,date,category\n")
      file.write("100.50,Test Transaction,2025-08-19,Food\n")
      file.rewind
      file
    end

    let(:uploaded_file) do
      ActionDispatch::Http::UploadedFile.new(
        tempfile: csv_file,
        filename: 'test.csv',
        type: 'text/csv'
      )
    end

    after { csv_file.close! }

    context 'synchronous import' do
      it 'imports transactions from CSV' do
        expect {
          post :import_csv, params: { file: uploaded_file }
        }.to change(Transaction, :count).by(1)
      end

      it 'returns import results' do
        post :import_csv, params: { file: uploaded_file }
        json = JSON.parse(response.body)
        expect(json).to include('message', 'imported', 'failed', 'errors', 'batch_id')
      end

      it 'processes CSV import synchronously by default' do
        expect(CsvImportService).to receive(:new).and_call_original
        expect(CsvImportJob).not_to receive(:perform_later)

        post :import_csv, params: { file: uploaded_file }
      end
    end

    context 'asynchronous import' do
      it 'queues CSV import job for background processing' do
        expect {
          post :import_csv, params: { file: uploaded_file, async: 'true' }
        }.to enqueue_job(CsvImportJob)
      end

      it 'returns accepted status for async import' do
        post :import_csv, params: { file: uploaded_file, async: 'true' }
        expect(response).to have_http_status(:accepted)
      end

      it 'returns job information for async import' do
        post :import_csv, params: { file: uploaded_file, async: 'true' }
        json = JSON.parse(response.body)
        expect(json).to include('message', 'job_id', 'status')
        expect(json['status']).to eq('queued')
      end

      it 'creates temporary file for async processing' do
        expect(File).to receive(:open).and_call_original
        expect(CsvImportJob).to receive(:perform_later).with(
          a_string_including('csv_import_'),
          'anonymous',
          run_anomaly_detection: false
        ).and_return(double(job_id: 'test-job-123'))

        post :import_csv, params: { file: uploaded_file, async: 'true' }
      end

      it 'passes anomaly detection option to job' do
        expect(CsvImportJob).to receive(:perform_later).with(
          any_args,
          run_anomaly_detection: true
        ).and_return(double(job_id: 'test-job-123'))

        post :import_csv, params: { file: uploaded_file, async: 'true', run_anomaly_detection: 'true' }
      end
    end

    context 'without file' do
      it 'returns unprocessable entity' do
        post :import_csv
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('No CSV file provided')
      end
    end

    context 'when import service fails' do
      before do
        allow_any_instance_of(CsvImportService).to receive(:import).and_raise(StandardError, 'Import failed')
      end

      it 'returns error response' do
        post :import_csv, params: { file: uploaded_file }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Import failed')
      end
    end
  end

  describe 'PATCH #bulk_update' do
    let!(:transactions) { create_list(:transaction, 3, status: 'pending') }
    let(:transaction_ids) { transactions.map(&:id) }

    it 'updates multiple transactions' do
      patch :bulk_update, params: {
        transaction_ids: transaction_ids,
        updates: { status: 'approved' }
      }

      transactions.each(&:reload)
      expect(transactions.all?(&:approved?)).to be true
    end

    it 'returns success response' do
      patch :bulk_update, params: {
        transaction_ids: transaction_ids,
        updates: { status: 'approved' }
      }

      expect(response).to be_successful
    end

    it 'returns updated transactions and message' do
      patch :bulk_update, params: {
        transaction_ids: transaction_ids,
        updates: { status: 'approved' }
      }

      json = JSON.parse(response.body)
      expect(json['message']).to include('3 transactions updated successfully')
      expect(json['transactions']).to be_an(Array)
      expect(json['transactions'].length).to eq(3)
    end

    context 'with non-existent IDs' do
      it 'ignores non-existent transactions' do
        patch :bulk_update, params: {
          transaction_ids: [ 999999, transaction_ids.first ],
          updates: { status: 'approved' }
        }

        json = JSON.parse(response.body)
        expect(json['message']).to include('1 transactions updated successfully')
      end
    end
  end

  describe 'GET #anomalies' do
    let!(:transaction_with_anomaly) { create(:transaction) }
    let!(:normal_transaction) { create(:transaction) }
    let!(:anomaly) { create(:anomaly_detection, transaction_record: transaction_with_anomaly) }

    it 'returns only transactions with anomalies' do
      get :anomalies
      json = JSON.parse(response.body)
      expect(json['transactions'].length).to eq(1)
      transaction_ids = json['transactions'].map { |t| t['id'] }
      expect(transaction_ids).to include(transaction_with_anomaly.id)
      expect(transaction_ids).not_to include(normal_transaction.id)
    end

    it 'includes anomaly details' do
      get :anomalies
      json = JSON.parse(response.body)
      expect(json['transactions'].first['anomalies']).to be_present
      expect(json['transactions'].first['anomalies'].first['id']).to eq(anomaly.id)
    end

    it 'eager loads associations' do
      expect(Transaction).to receive(:with_anomalies).and_call_original
      expect_any_instance_of(ActiveRecord::Relation).to receive(:includes).with(:category).and_call_original

      get :anomalies
    end

    it 'includes pagination metadata' do
      get :anomalies
      json = JSON.parse(response.body)
      expect(json).to have_key('pagination')
      expect(json['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
    end

    it 'handles pagination correctly' do
      # Create more transactions with anomalies
      5.times { create(:anomaly_detection, transaction_record: create(:transaction)) }

      get :anomalies, params: { per_page: 2 }
      json = JSON.parse(response.body)
      expect(json['transactions'].length).to eq(2)
      expect(json['pagination']['total_count']).to be > 0
      expect(json['pagination']['per_page']).to eq(2)
    end

    context 'with status filtering' do
      let!(:flagged_transaction) { create(:transaction, status: 'flagged') }
      let!(:pending_transaction) { create(:transaction, status: 'pending') }
      let!(:flagged_anomaly) { create(:anomaly_detection, transaction_record: flagged_transaction) }
      let!(:pending_anomaly) { create(:anomaly_detection, transaction_record: pending_transaction) }

      it 'filters by flagged status' do
        get :anomalies, params: { status: 'flagged' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['status']).to eq('flagged')
        expect(json['transactions'].first['id']).to eq(flagged_transaction.id)
      end

      it 'filters by pending status' do
        get :anomalies, params: { status: 'pending' }
        json = JSON.parse(response.body)
        # Should include pending transactions (with and without anomalies)
        pending_transaction_ids = json['transactions'].map { |t| t['id'] }
        expect(pending_transaction_ids).to include(pending_transaction.id)
      end

      it 'shows transactions with anomalies when no status filter provided' do
        get :anomalies
        json = JSON.parse(response.body)
        # Should show transactions that have anomalies regardless of status
        transaction_ids = json['transactions'].map { |t| t['id'] }
        expect(transaction_ids).to include(flagged_transaction.id)
        expect(transaction_ids).to include(pending_transaction.id)
      end
    end

    context 'with anomaly type filtering' do
      before do
        # Clean up any existing test data to avoid interference
        AnomalyDetection.delete_all
        Transaction.delete_all
      end

      let!(:unusual_amount_transaction) { create(:transaction) }
      let!(:duplicate_transaction) { create(:transaction) }
      let!(:unusual_anomaly) { create(:anomaly_detection, transaction_record: unusual_amount_transaction, anomaly_type: 'unusual_amount') }
      let!(:duplicate_anomaly) { create(:anomaly_detection, transaction_record: duplicate_transaction, anomaly_type: 'duplicate_transaction') }

      it 'filters by unusual_amount anomaly type' do
        get :anomalies, params: { anomaly_type: 'unusual_amount' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['id']).to eq(unusual_amount_transaction.id)
      end

      it 'filters by duplicate_transaction anomaly type' do
        get :anomalies, params: { anomaly_type: 'duplicate_transaction' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['id']).to eq(duplicate_transaction.id)
      end
    end

    context 'with combined filtering' do
      let!(:flagged_unusual) { create(:transaction, status: 'flagged') }
      let!(:pending_unusual) { create(:transaction, status: 'pending') }
      let!(:flagged_unusual_anomaly) { create(:anomaly_detection, transaction_record: flagged_unusual, anomaly_type: 'unusual_amount') }
      let!(:pending_unusual_anomaly) { create(:anomaly_detection, transaction_record: pending_unusual, anomaly_type: 'unusual_amount') }

      it 'can combine status and anomaly type filters' do
        get :anomalies, params: { status: 'flagged', anomaly_type: 'unusual_amount' }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['id']).to eq(flagged_unusual.id)
        expect(json['transactions'].first['status']).to eq('flagged')
      end
    end

    context 'with show_all parameter' do
      it 'returns all transactions when show_all=true' do
        get :anomalies, params: { show_all: 'true' }
        json = JSON.parse(response.body)

        # Should return both transactions with and without anomalies
        expect(json['transactions'].length).to be >= 2
        transaction_ids = json['transactions'].map { |t| t['id'] }
        expect(transaction_ids).to include(transaction_with_anomaly.id)
        expect(transaction_ids).to include(normal_transaction.id)
      end

      it 'still applies other filters when show_all=true' do
        # Create a pending transaction and a flagged transaction
        pending_transaction = create(:transaction, status: 'pending')
        flagged_transaction = create(:transaction, status: 'flagged')

        get :anomalies, params: { show_all: 'true', status: 'pending' }
        json = JSON.parse(response.body)

        # Should only return pending transactions
        expect(json['transactions'].all? { |t| t['status'] == 'pending' }).to be true
      end

      it 'defaults to transactions with anomalies when show_all is not specified' do
        get :anomalies
        json = JSON.parse(response.body)

        # Should only return transactions with anomalies (default behavior)
        expect(json['transactions'].length).to eq(1)
        expect(json['transactions'].first['id']).to eq(transaction_with_anomaly.id)
      end
    end
  end
end
