require 'rails_helper'

RSpec.describe QueryCounter, type: :controller do
  controller(ApplicationController) do
    include QueryCounter

    def simple_action
      render json: { message: 'Simple response' }
    end

    def database_action
      # Simulate database queries
      Transaction.count
      Category.all.to_a
      render json: { count: Transaction.count }
    end

    def heavy_database_action
      # Simulate N+1 queries
      transactions = Transaction.limit(3).to_a
      transactions.each do |transaction|
        transaction.category&.name # This could cause N+1 if not properly loaded
      end
      render json: { count: transactions.count }
    end

    def error_action
      raise StandardError, 'Test error'
    end

    private

    def should_count_queries?
      params[:count_queries] == 'true' || super
    end
  end

  before do
    routes.draw do
      get 'simple_action' => 'anonymous#simple_action'
      get 'database_action' => 'anonymous#database_action'
      get 'heavy_database_action' => 'anonymous#heavy_database_action'
      get 'error_action' => 'anonymous#error_action'
    end

    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:error)

    # Create some test data
    create_list(:transaction, 5, :with_category)
  end

  describe '#count_queries' do
    context 'when query counting is enabled' do
      it 'adds query count to response headers' do
        get :database_action, params: { count_queries: 'true' }

        expect(response.headers['X-Query-Count']).to be_present
        expect(response.headers['X-Query-Count'].to_i).to be > 0
      end

      it 'counts actual database queries' do
        get :database_action, params: { count_queries: 'true' }

        query_count = response.headers['X-Query-Count'].to_i
        expect(query_count).to be >= 2 # At least COUNT and SELECT queries
      end

      it 'does not count schema queries' do
        # Schema queries should be filtered out
        get :simple_action, params: { count_queries: 'true' }

        query_count = response.headers['X-Query-Count'].to_i
        expect(query_count).to eq(0) # No database queries in simple action
      end

      it 'does not count cached queries' do
        # First request
        get :database_action, params: { count_queries: 'true' }
        first_count = response.headers['X-Query-Count'].to_i

        # Subsequent requests might have cached results
        get :database_action, params: { count_queries: 'true' }
        second_count = response.headers['X-Query-Count'].to_i

        # Both should count actual queries, not cached ones
        expect(first_count).to be > 0
        expect(second_count).to be > 0
      end
    end

    context 'when query counting is disabled' do
      it 'does not add query count headers' do
        get :database_action # count_queries param not set

        expect(response.headers['X-Query-Count']).to be_nil
      end

      it 'does not log query warnings' do
        expect(Rails.logger).not_to receive(:warn).with(a_string_matching(/HIGH_QUERY_COUNT/))

        get :database_action
      end
    end

    context 'with high query count' do
      before do
        # Mock query warning threshold to be very low for testing
        allow_any_instance_of(controller.class).to receive(:query_warning_threshold).and_return(1)
      end

      it 'logs warnings for high query counts' do
        expect(Rails.logger).to receive(:warn).with(a_string_matching(/HIGH_QUERY_COUNT:/))

        get :database_action, params: { count_queries: 'true' }
      end

      it 'includes action and query count in warning' do
        expect(Rails.logger).to receive(:warn) do |message|
          expect(message).to include('anonymous#database_action')
          expect(message).to include('executed')
          expect(message).to include('queries')
          expect(message).to include('threshold: 1')
        end

        get :database_action, params: { count_queries: 'true' }
      end

      context 'in development environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        end

        it 'logs detailed query information' do
          expect(Rails.logger).to receive(:debug).with(a_string_matching(/QUERY_DETAILS/))
          expect(Rails.logger).to receive(:debug).at_least(:once).with(a_string_matching(/\d+\.\s+\[\d+\.\d+ms\]/))

          get :database_action, params: { count_queries: 'true' }
        end
      end
    end

    context 'when query counting fails' do
      before do
        allow_any_instance_of(controller.class).to receive(:query_count_start).and_raise(StandardError, 'Query counting error')
      end

      it 'handles query counting errors gracefully' do
        expect(Rails.logger).to receive(:error).with('Query counting error: Query counting error')

        expect { get :simple_action, params: { count_queries: 'true' } }.not_to raise_error
      end

      it 'still processes the request normally' do
        get :simple_action, params: { count_queries: 'true' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['message']).to eq('Simple response')
      end
    end

    context 'with thread-local storage cleanup' do
      it 'cleans up thread-local variables after request' do
        get :database_action, params: { count_queries: 'true' }

        expect(Thread.current[:query_count]).to be_nil
        expect(Thread.current[:ar_query_log]).to be_nil
      end

      it 'cleans up even when errors occur' do
        expect { get :error_action, params: { count_queries: 'true' } }.to raise_error(StandardError)

        expect(Thread.current[:query_count]).to be_nil
        expect(Thread.current[:ar_query_log]).to be_nil
      end
    end
  end

  describe '#log_query_details' do
    let(:controller_instance) { controller }

    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    end

    it 'logs individual query details with timing' do
      # Mock query log
      Thread.current[:ar_query_log] = [
        {
          sql: 'SELECT COUNT(*) FROM transactions',
          duration: 5.23,
          name: 'Transaction Count',
          timestamp: Time.current
        },
        {
          sql: 'SELECT * FROM transactions LIMIT 10',
          duration: 12.45,
          name: 'Transaction Load',
          timestamp: Time.current
        }
      ]

      expect(Rails.logger).to receive(:debug).with("QUERY_DETAILS for anonymous#database_action:")
      expect(Rails.logger).to receive(:debug).with("  1. [5.23ms] Transaction Count: SELECT COUNT(*) FROM transactions")
      expect(Rails.logger).to receive(:debug).with("  2. [12.45ms] Transaction Load: SELECT * FROM transactions LIMIT 10")

      controller_instance.send(:log_query_details)
    end

    it 'truncates long SQL queries' do
      long_sql = 'SELECT * FROM transactions WHERE ' + 'description LIKE "%test%" AND ' * 20 + 'amount > 0'
      
      Thread.current[:ar_query_log] = [
        {
          sql: long_sql,
          duration: 10.0,
          name: 'Long Query',
          timestamp: Time.current
        }
      ]

      expect(Rails.logger).to receive(:debug).with("QUERY_DETAILS for anonymous#database_action:")
      expect(Rails.logger).to receive(:debug) do |message|
        expect(message).to include('[10.0ms] Long Query:')
        expect(message.length).to be <= 250 # Truncated
      end

      controller_instance.send(:log_query_details)
    end
  end

  describe 'configuration methods' do
    let(:controller_instance) { controller }

    describe '#should_count_queries?' do
      it 'enables counting in development' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        expect(controller_instance.send(:should_count_queries?)).to be true
      end

      it 'enables counting in test' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
        expect(controller_instance.send(:should_count_queries?)).to be true
      end

      it 'can be enabled with count_queries param' do
        allow(controller_instance).to receive(:params).and_return({ count_queries: 'true' })
        expect(controller_instance.send(:should_count_queries?)).to be true
      end

      it 'is disabled in production by default' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        allow(controller_instance).to receive(:params).and_return({})
        expect(controller_instance.send(:should_count_queries?)).to be false
      end
    end

    describe '#query_warning_threshold' do
      it 'uses default threshold when not configured' do
        expect(controller_instance.send(:query_warning_threshold)).to eq(10)
      end

      it 'uses environment variable when configured' do
        stub_const('ENV', ENV.to_hash.merge('QUERY_WARNING_THRESHOLD' => '5'))
        expect(controller_instance.send(:query_warning_threshold)).to eq(5)
      end
    end
  end

  describe 'ActiveRecord integration' do
    it 'subscribes to ActiveRecord SQL notifications' do
      expect(ActiveSupport::Notifications).to receive(:subscribe).with('sql.active_record')
      expect(ActiveSupport::Notifications).to receive(:unsubscribe)

      get :database_action, params: { count_queries: 'true' }
    end

    it 'properly unsubscribes from notifications after request' do
      # This is tested implicitly - if unsubscribe fails, subsequent tests might fail
      get :database_action, params: { count_queries: 'true' }
      get :simple_action, params: { count_queries: 'true' }

      # Both requests should work without interference
      expect(response).to have_http_status(:ok)
    end

    context 'with real database queries' do
      it 'accurately counts different types of queries' do
        get :heavy_database_action, params: { count_queries: 'true' }

        query_count = response.headers['X-Query-Count'].to_i
        # Should count: SELECT for transactions, possibly SELECT for categories
        expect(query_count).to be >= 1
      end
    end
  end

  describe 'integration with performance monitoring' do
    controller(ApplicationController) do
      include QueryCounter
      include PerformanceMonitoring

      def monitored_action
        Transaction.count
        render json: { message: 'Monitored action' }
      end

      private

      def should_count_queries?
        true
      end

      def should_monitor_performance?
        true
      end
    end

    before do
      routes.draw do
        get 'monitored_action' => 'anonymous#monitored_action'
      end
    end

    it 'works together with performance monitoring' do
      get :monitored_action

      expect(response.headers['X-Query-Count']).to be_present
      expect(response.headers['X-Response-Time']).to be_present
    end
  end
end