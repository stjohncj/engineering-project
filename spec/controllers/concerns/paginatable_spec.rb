require 'rails_helper'

RSpec.describe Paginatable, type: :controller do
  controller(ApplicationController) do
    include Paginatable

    def index
      @transactions = Transaction.all
      paginated = paginate_collection(@transactions)
      render json: paginated_json(paginated, data_key: :transactions)
    end

    def show_with_meta
      @transactions = Transaction.all
      paginated = paginate_collection(@transactions)
      meta = pagination_meta(paginated)
      render json: { data: paginated, meta: meta }
    end
  end

  let!(:transactions) { create_list(:transaction, 15) }

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'show_with_meta' => 'anonymous#show_with_meta'
    end
  end

  describe '#paginate_collection' do
    context 'with default pagination' do
      it 'paginates with default settings' do
        get :index

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['transactions'].length).to eq(15) # All fit in default page size
        expect(json['pagination']['current_page']).to eq(1)
        expect(json['pagination']['per_page']).to eq(50) # DEFAULT_PER_PAGE
      end
    end

    context 'with custom page parameters' do
      it 'respects page parameter' do
        get :index, params: { page: 2, per_page: 5 }

        json = JSON.parse(response.body)

        expect(json['transactions'].length).to eq(5)
        expect(json['pagination']['current_page']).to eq(2)
        expect(json['pagination']['per_page']).to eq(5)
      end

      it 'limits per_page to MAX_PER_PAGE' do
        get :index, params: { per_page: 200 }

        json = JSON.parse(response.body)

        expect(json['pagination']['per_page']).to eq(100) # MAX_PER_PAGE
      end

      it 'handles invalid page numbers gracefully' do
        get :index, params: { page: 0 }

        json = JSON.parse(response.body)

        expect(json['pagination']['current_page']).to eq(1) # Defaults to 1
      end
    end

    context 'with large dataset' do
      before do
        create_list(:transaction, 125) # Total 140 transactions
      end

      it 'properly paginates large datasets' do
        get :index, params: { page: 2, per_page: 50 }

        json = JSON.parse(response.body)

        expect(json['transactions'].length).to eq(50)
        expect(json['pagination']['current_page']).to eq(2)
        expect(json['pagination']['total_count']).to eq(140)
        expect(json['pagination']['total_pages']).to eq(3)
      end
    end
  end

  describe '#pagination_meta' do
    it 'returns comprehensive pagination metadata' do
      get :show_with_meta, params: { page: 2, per_page: 5 }

      json = JSON.parse(response.body)
      meta = json['meta']

      expect(meta).to include(
        'current_page' => 2,
        'per_page' => 5,
        'total_count' => 15,
        'total_pages' => 3,
        'next_page' => 3,
        'prev_page' => 1
      )
    end

    it 'handles first page correctly' do
      get :show_with_meta, params: { page: 1, per_page: 5 }

      json = JSON.parse(response.body)
      meta = json['meta']

      expect(meta['prev_page']).to be_nil
      expect(meta['next_page']).to eq(2)
    end

    it 'handles last page correctly' do
      get :show_with_meta, params: { page: 3, per_page: 5 }

      json = JSON.parse(response.body)
      meta = json['meta']

      expect(meta['next_page']).to be_nil
      expect(meta['prev_page']).to eq(2)
    end
  end

  describe '#get_total_count' do
    it 'caches total count for expensive queries' do
      controller_instance = controller
      collection = Transaction.all.offset(10).limit(5)

      expect(Rails.cache).to receive(:fetch).with(
        a_string_starting_with("total_count_"),
        expires_in: 5.minutes
      ).and_return(15)

      count = controller_instance.send(:get_total_count, collection)
      expect(count).to eq(15)
    end

    it 'excludes offset and limit from count query' do
      controller_instance = controller
      collection = Transaction.all.offset(10).limit(5).order(:created_at)

      # Should count the base relation without offset/limit
      expect(controller_instance.send(:get_total_count, collection)).to eq(15)
    end
  end

  describe '#paginated_json' do
    it 'returns properly structured JSON with default data key' do
      get :index, params: { page: 1, per_page: 10 }

      json = JSON.parse(response.body)

      expect(json).to have_key('transactions')
      expect(json).to have_key('pagination')
      expect(json['transactions']).to be_an(Array)
      expect(json['pagination']).to be_a(Hash)
    end

    context 'with custom data key' do
      controller(ApplicationController) do
        include Paginatable

        def custom_key
          @transactions = Transaction.all
          paginated = paginate_collection(@transactions)
          render json: paginated_json(paginated, data_key: :items)
        end
      end

      before do
        routes.draw do
          get 'custom_key' => 'anonymous#custom_key'
        end
      end

      it 'uses custom data key' do
        get :custom_key

        json = JSON.parse(response.body)

        expect(json).to have_key('items')
        expect(json).not_to have_key('transactions')
      end
    end
  end

  describe 'edge cases' do
    context 'with no records' do
      before do
        Transaction.destroy_all
      end

      it 'handles empty collections gracefully' do
        get :index

        json = JSON.parse(response.body)

        expect(json['transactions']).to eq([])
        expect(json['pagination']['total_count']).to eq(0)
        expect(json['pagination']['total_pages']).to eq(0)
        expect(json['pagination']['next_page']).to be_nil
        expect(json['pagination']['prev_page']).to be_nil
      end
    end

    context 'with page beyond total pages' do
      it 'returns empty results for pages beyond total' do
        get :index, params: { page: 999, per_page: 10 }

        json = JSON.parse(response.body)

        expect(json['transactions']).to eq([])
        expect(json['pagination']['current_page']).to eq(999)
        expect(json['pagination']['total_count']).to eq(15)
      end
    end
  end

  describe 'integration with ActiveRecord' do
    context 'with filtered collections' do
      let!(:category) { create(:category, name: 'Test') }
      let!(:categorized_transactions) { create_list(:transaction, 5, category: category) }

      controller(ApplicationController) do
        include Paginatable

        def filtered
          @transactions = Transaction.joins(:category).where(categories: { name: 'Test' })
          paginated = paginate_collection(@transactions)
          render json: paginated_json(paginated, data_key: :transactions)
        end
      end

      before do
        routes.draw do
          get 'filtered' => 'anonymous#filtered'
        end
      end

      it 'works with complex ActiveRecord queries' do
        get :filtered

        json = JSON.parse(response.body)

        expect(json['transactions'].length).to eq(5)
        expect(json['pagination']['total_count']).to eq(5)
      end
    end

    context 'with ordering' do
      controller(ApplicationController) do
        include Paginatable

        def ordered
          @transactions = Transaction.order(created_at: :desc)
          paginated = paginate_collection(@transactions)
          render json: paginated_json(paginated, data_key: :transactions)
        end
      end

      before do
        routes.draw do
          get 'ordered' => 'anonymous#ordered'
        end
      end

      it 'preserves ordering in paginated results' do
        # Create transactions with specific timestamps
        old_transaction = create(:transaction, created_at: 1.hour.ago)
        new_transaction = create(:transaction, created_at: 30.minutes.ago)

        get :ordered, params: { per_page: 5 }

        json = JSON.parse(response.body)

        # Should be ordered by created_at desc
        first_transaction_id = json['transactions'].first['id']
        expect(first_transaction_id).to eq(new_transaction.id)
      end
    end
  end

  describe 'performance considerations' do
    it 'uses efficient queries for large datasets' do
      # Create a larger dataset
      create_list(:transaction, 500)

      expect {
        get :index, params: { page: 10, per_page: 50 }
      }.to make_database_queries(count: be <= 3) # Should be minimal queries
    end

    it 'caches count queries to avoid expensive recalculation' do
      controller_instance = controller
      collection = Transaction.all

      # First call should hit the database and cache
      expect(Rails.cache).to receive(:fetch).and_call_original
      controller_instance.send(:get_total_count, collection)

      # Subsequent calls should use cache
      expect(Rails.cache).to receive(:fetch).and_return(15)
      controller_instance.send(:get_total_count, collection)
    end
  end
end
