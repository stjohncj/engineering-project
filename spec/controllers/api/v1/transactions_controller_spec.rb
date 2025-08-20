require 'rails_helper'

RSpec.describe Api::V1::TransactionsController, type: :controller do
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
      expect(json['pagination']).to include('current_page', 'per_page', 'total_count')
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

      it 'paginates results' do
        get :index, params: { per_page: 10 }
        json = JSON.parse(response.body)
        expect(json['transactions'].length).to eq(10)
        expect(json['pagination']['total_count']).to eq(28) # 25 + 3 from earlier
      end

      it 'returns specific page' do
        get :index, params: { page: 2, per_page: 10 }
        json = JSON.parse(response.body)
        expect(json['pagination']['current_page']).to eq(2)
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

  describe 'POST #import' do
    let(:csv_file) do
      file = Tempfile.new(['test', '.csv'])
      file.write("date,description,amount,category\n")
      file.write("2024-01-15,Test Transaction,-50.00,Test\n")
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

    it 'imports transactions from CSV' do
      expect {
        post :import, params: { file: uploaded_file }
      }.to change(Transaction, :count).by(1)
    end

    it 'returns import results' do
      post :import, params: { file: uploaded_file }
      json = JSON.parse(response.body)
      expect(json).to include('processed_count', 'imported_count', 'error_count')
    end

    context 'without file' do
      it 'returns bad request' do
        post :import
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with invalid file type' do
      let(:text_file) do
        file = Tempfile.new(['test', '.txt'])
        file.write("This is not a CSV file")
        file.rewind
        file
      end

      let(:uploaded_text_file) do
        ActionDispatch::Http::UploadedFile.new(
          tempfile: text_file,
          filename: 'test.txt',
          type: 'text/plain'
        )
      end

      after { text_file.close! }

      it 'returns bad request for non-CSV files' do
        post :import, params: { file: uploaded_text_file }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'PATCH #bulk_update' do
    let!(:transactions) { create_list(:transaction, 3, status: 'pending') }
    let(:transaction_ids) { transactions.map(&:id) }

    it 'updates multiple transactions' do
      patch :bulk_update, params: { 
        ids: transaction_ids, 
        updates: { status: 'approved' } 
      }
      
      transactions.each(&:reload)
      expect(transactions.all?(&:approved?)).to be true
    end

    it 'returns success response' do
      patch :bulk_update, params: { 
        ids: transaction_ids, 
        updates: { status: 'approved' } 
      }
      
      expect(response).to be_successful
    end

    it 'returns updated count' do
      patch :bulk_update, params: { 
        ids: transaction_ids, 
        updates: { status: 'approved' } 
      }
      
      json = JSON.parse(response.body)
      expect(json['updated_count']).to eq(3)
    end

    context 'with non-existent IDs' do
      it 'ignores non-existent transactions' do
        patch :bulk_update, params: { 
          ids: [999999, transaction_ids.first], 
          updates: { status: 'approved' } 
        }
        
        json = JSON.parse(response.body)
        expect(json['updated_count']).to eq(1)
      end
    end
  end

  describe 'GET #anomalies' do
    let!(:flagged_transaction) { create(:transaction, :flagged) }
    let!(:normal_transaction) { create(:transaction, :approved) }

    it 'returns only flagged transactions' do
      get :anomalies
      json = JSON.parse(response.body)
      expect(json['transactions'].length).to eq(1)
      expect(json['transactions'].first['status']).to eq('flagged')
    end

    it 'includes anomaly details' do
      anomaly = create(:anomaly_detection, transaction: flagged_transaction)
      get :anomalies
      json = JSON.parse(response.body)
      expect(json['transactions'].first['anomalies']).to be_present
    end
  end
end