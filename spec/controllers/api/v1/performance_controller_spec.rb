require 'rails_helper'

RSpec.describe Api::V1::PerformanceController, type: :controller do
  describe 'GET #health' do
    it 'returns health status' do
      get :health

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('healthy')
      expect(json_response['timestamp']).to be_present
      expect(json_response['version']).to be_present
      expect(json_response['environment']).to eq(Rails.env)
    end

    it 'includes current timestamp in ISO format' do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      get :health

      json_response = JSON.parse(response.body)
      expect(json_response['timestamp']).to eq(freeze_time.iso8601)
    end
  end

  describe 'GET #metrics' do
    let(:mock_metrics) do
      {
        memory_usage: 128.5,
        gc_stats: { count: 100 },
        object_count: { TOTAL: 50000 },
        uptime: 3600,
        ruby_version: RUBY_VERSION,
        rails_version: Rails.version
      }
    end

    before do
      allow(Rails.cache).to receive(:fetch).with('system_metrics', expires_in: 1.minute).and_return(mock_metrics)
    end

    it 'returns cached system metrics' do
      get :metrics

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['metrics']).to eq(mock_metrics.as_json)
      expect(json_response['timestamp']).to be_present
    end

    it 'caches metrics for 1 minute' do
      expect(Rails.cache).to receive(:fetch).with('system_metrics', expires_in: 1.minute)

      get :metrics
    end
  end

  describe 'GET #database_stats' do
    let(:mock_connection_pool) do
      double('connection_pool',
        size: 5,
        checked_out: double(size: 2),
        available: double(size: 3)
      )
    end

    let(:mock_db_stats) do
      {
        connection_pool: {
          size: 5,
          checked_out: 2,
          available: 3
        },
        table_counts: {
          transactions: 1000,
          categories: 10,
          rules: 5,
          anomaly_detections: 50
        },
        largest_tables: [
          { 'tablename' => 'transactions', 'size' => '1 MB' }
        ],
        slow_queries: { message: 'Slow query tracking not implemented' }
      }
    end

    before do
      allow(Rails.cache).to receive(:fetch).with('database_stats', expires_in: 5.minutes).and_return(mock_db_stats)
    end

    it 'returns cached database statistics' do
      get :database_stats

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['database']).to eq(mock_db_stats.as_json)
      expect(json_response['timestamp']).to be_present
    end

    it 'caches database stats for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with('database_stats', expires_in: 5.minutes)

      get :database_stats
    end
  end

  describe 'GET #cache_stats' do
    context 'when cache supports stats' do
      let(:mock_cache_stats) do
        {
          hits: 1000,
          misses: 200,
          hit_rate: 0.83
        }
      end

      before do
        allow(Rails.cache).to receive(:respond_to?).with(:stats).and_return(true)
        allow(Rails.cache).to receive(:stats).and_return(mock_cache_stats)
      end

      it 'returns cache statistics' do
        get :cache_stats

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['cache']).to eq(mock_cache_stats.as_json)
        expect(json_response['timestamp']).to be_present
      end
    end

    context 'when cache does not support stats' do
      before do
        allow(Rails.cache).to receive(:respond_to?).with(:stats).and_return(false)
      end

      it 'returns unavailable message' do
        get :cache_stats

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['cache']['message']).to eq('Cache stats not available for this cache store')
        expect(json_response['timestamp']).to be_present
      end
    end
  end

  describe 'private methods' do
    let(:controller_instance) { described_class.new }

    describe '#calculate_system_metrics' do
      it 'includes expected metric keys' do
        metrics = controller_instance.send(:calculate_system_metrics)

        expect(metrics).to have_key(:memory_usage)
        expect(metrics).to have_key(:gc_stats)
        expect(metrics).to have_key(:object_count)
        expect(metrics).to have_key(:uptime)
        expect(metrics).to have_key(:ruby_version)
        expect(metrics).to have_key(:rails_version)
      end

      context 'when metric collection fails' do
        before do
          allow(GC).to receive(:stat).and_raise(StandardError, "GC error")
        end

        it 'returns error message' do
          metrics = controller_instance.send(:calculate_system_metrics)

          expect(metrics[:error]).to include("Unable to collect system metrics")
        end
      end
    end

    describe '#calculate_database_stats' do
      let(:mock_connection_pool) do
        double('connection_pool',
          size: 5,
          checked_out: double(size: 2),
          available: double(size: 3)
        )
      end

      before do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(mock_connection_pool)
        allow(Transaction).to receive(:count).and_return(1000)
        allow(Category).to receive(:count).and_return(10)
        allow(Rule).to receive(:count).and_return(5)
        allow(AnomalyDetection).to receive(:count).and_return(50)
      end

      it 'includes database connection and table information' do
        stats = controller_instance.send(:calculate_database_stats)

        expect(stats[:connection_pool][:size]).to eq(5)
        expect(stats[:connection_pool][:checked_out]).to eq(2)
        expect(stats[:connection_pool][:available]).to eq(3)

        expect(stats[:table_counts][:transactions]).to eq(1000)
        expect(stats[:table_counts][:categories]).to eq(10)
        expect(stats[:table_counts][:rules]).to eq(5)
        expect(stats[:table_counts][:anomaly_detections]).to eq(50)
      end

      context 'when database query fails' do
        before do
          allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(StandardError, "DB error")
        end

        it 'returns error message' do
          stats = controller_instance.send(:calculate_database_stats)

          expect(stats[:error]).to include("Unable to collect database stats")
        end
      end
    end

    describe '#get_memory_usage' do
      it 'returns memory usage in MB' do
        memory_usage = controller_instance.send(:get_memory_usage)

        expect(memory_usage).to be_a(Numeric)
        expect(memory_usage).to be >= 0
      end

      context 'when GC stats are unavailable' do
        before do
          allow(GC).to receive(:stat).and_raise(StandardError)
        end

        it 'returns 0' do
          memory_usage = controller_instance.send(:get_memory_usage)

          expect(memory_usage).to eq(0)
        end
      end
    end

    describe '#get_table_sizes' do
      context 'when using PostgreSQL' do
        before do
          allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return('PostgreSQL')
          allow(ActiveRecord::Base.connection).to receive(:exec_query).and_return([
            { 'tablename' => 'transactions', 'size' => '1 MB', 'size_bytes' => 1048576 }
          ])
        end

        it 'returns table size information' do
          sizes = controller_instance.send(:get_table_sizes)

          expect(sizes).to be_an(Array)
          expect(sizes.first['tablename']).to eq('transactions')
        end
      end

      context 'when not using PostgreSQL' do
        before do
          allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return('SQLite')
        end

        it 'returns empty hash' do
          sizes = controller_instance.send(:get_table_sizes)

          expect(sizes).to eq({})
        end
      end

      context 'when query fails' do
        before do
          allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return('PostgreSQL')
          allow(ActiveRecord::Base.connection).to receive(:exec_query).and_raise(StandardError, "Query failed")
        end

        it 'returns error message' do
          sizes = controller_instance.send(:get_table_sizes)

          expect(sizes[:error]).to include("Unable to get table sizes")
        end
      end
    end

    describe '#get_recent_slow_queries' do
      it 'returns placeholder message' do
        slow_queries = controller_instance.send(:get_recent_slow_queries)

        expect(slow_queries[:message]).to eq('Slow query tracking not implemented')
      end
    end
  end
end
