require 'rails_helper'

RSpec.describe Api::V1::DashboardController, type: :controller do
  let!(:category) { create(:category, name: 'Food & Dining') }
  let!(:transactions) { create_list(:transaction, 3, category: category, amount: 100.0) }
  let!(:anomaly) { create(:anomaly_detection, transaction_record: transactions.first, resolved: false) }

  before do
    # Clear cache before each test
    Rails.cache.clear
    # Clean up any existing test data to ensure isolation
    Transaction.where.not(id: [transactions.map(&:id)].flatten).delete_all
  end

  describe 'GET #statistics' do
    it 'returns cached dashboard statistics' do
      get :statistics

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      statistics = json_response['statistics']

      expect(statistics['total_transactions']).to eq(3)
      expect(statistics['total_amount']).to eq(300.0)
      expect(statistics['active_rules']).to be_a(Integer)
      expect(statistics['unresolved_anomalies']).to eq(1)
      expect(statistics['categories_count']).to eq(1)
      expect(statistics).to have_key('monthly_trends')
      expect(statistics).to have_key('category_breakdown')
    end

    it 'caches statistics for 5 minutes' do
      # Mock the cache to verify caching behavior
      allow(Rails.cache).to receive(:fetch).and_call_original
      expect(Rails.cache).to receive(:fetch).with("dashboard_statistics", expires_in: 5.minutes).and_call_original

      get :statistics

      expect(response).to have_http_status(:ok)
    end

    it 'includes monthly trends data' do
      get :statistics

      json_response = JSON.parse(response.body)
      statistics = json_response['statistics']

      expect(statistics['monthly_trends']).to be_a(Hash)
    end

    it 'includes category breakdown data' do
      get :statistics

      json_response = JSON.parse(response.body)
      statistics = json_response['statistics']

      expect(statistics['category_breakdown']).to be_an(Array)
      expect(statistics['category_breakdown'].first).to have_key('category')
      expect(statistics['category_breakdown'].first).to have_key('count')
      expect(statistics['category_breakdown'].first).to have_key('total_amount')
    end
  end

  describe 'GET #recent_transactions' do
    it 'returns cached recent transactions' do
      get :recent_transactions

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      transactions_data = json_response['transactions']

      expect(transactions_data).to be_an(Array)
      expect(transactions_data.length).to be <= 10
      expect(transactions_data.first).to have_key('id')
      expect(transactions_data.first).to have_key('amount')
      expect(transactions_data.first).to have_key('description')
      expect(transactions_data.first).to have_key('category')
      expect(transactions_data.first).to have_key('anomaly_count')
    end

    it 'caches recent transactions for 1 minute' do
      expect(Rails.cache).to receive(:fetch).with("recent_transactions", expires_in: 1.minute).and_call_original

      get :recent_transactions

      expect(response).to have_http_status(:ok)
    end

    it 'orders transactions by creation date descending' do
      # Clear existing data and create transactions with specific timestamps
      AnomalyDetection.delete_all
      Transaction.delete_all
      
      old_transaction = create(:transaction, category: category, created_at: 2.hours.ago)
      new_transaction = create(:transaction, category: category, created_at: 1.hour.ago)

      get :recent_transactions

      json_response = JSON.parse(response.body)
      transactions_data = json_response['transactions']

      expect(transactions_data.first['id']).to eq(new_transaction.id)
    end

    it 'includes anomaly count for transactions' do
      # Transaction with anomaly should show count
      get :recent_transactions

      json_response = JSON.parse(response.body)
      transactions_data = json_response['transactions']

      transaction_with_anomaly = transactions_data.find { |t| t['id'] == transactions.first.id }
      expect(transaction_with_anomaly['anomaly_count']).to eq(1)
    end
  end

  describe 'GET #active_anomalies' do
    let!(:resolved_anomaly) { create(:anomaly_detection, transaction_record: transactions.second, resolved: true) }
    let!(:high_severity_anomaly) { create(:anomaly_detection, transaction_record: transactions.third, resolved: false, severity: 5) }

    it 'returns cached active anomalies' do
      get :active_anomalies

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      anomalies_data = json_response['anomalies']

      expect(anomalies_data).to be_an(Array)
      expect(anomalies_data.length).to be <= 5
      expect(anomalies_data.first).to have_key('id')
      expect(anomalies_data.first).to have_key('type')
      expect(anomalies_data.first).to have_key('severity')
      expect(anomalies_data.first).to have_key('severity_label')
      expect(anomalies_data.first).to have_key('description')
      expect(anomalies_data.first).to have_key('transaction_id')
      expect(anomalies_data.first).to have_key('detected_at')
    end

    it 'caches active anomalies for 2 minutes' do
      expect(Rails.cache).to receive(:fetch).with("active_anomalies", expires_in: 2.minutes).and_call_original

      get :active_anomalies

      expect(response).to have_http_status(:ok)
    end

    it 'only returns unresolved anomalies' do
      get :active_anomalies

      json_response = JSON.parse(response.body)
      anomalies_data = json_response['anomalies']

      # Should not include the resolved anomaly
      resolved_anomaly_ids = anomalies_data.map { |a| a['id'] }
      expect(resolved_anomaly_ids).not_to include(resolved_anomaly.id)
      expect(resolved_anomaly_ids).to include(anomaly.id)
      expect(resolved_anomaly_ids).to include(high_severity_anomaly.id)
    end

    it 'orders anomalies by severity and creation date' do
      get :active_anomalies

      json_response = JSON.parse(response.body)
      anomalies_data = json_response['anomalies']

      # High severity anomaly should come first
      expect(anomalies_data.first['id']).to eq(high_severity_anomaly.id)
      expect(anomalies_data.first['severity']).to eq(5)
    end

    it 'limits results to 5 anomalies' do
      # Create more than 5 anomalies
      create_list(:anomaly_detection, 6, resolved: false)

      get :active_anomalies

      json_response = JSON.parse(response.body)
      anomalies_data = json_response['anomalies']

      expect(anomalies_data.length).to eq(5)
    end
  end

  describe 'private methods' do
    let(:controller_instance) { described_class.new }

    describe '#calculate_statistics' do
      it 'returns comprehensive statistics' do
        stats = controller_instance.send(:calculate_statistics)

        expect(stats).to have_key(:total_transactions)
        expect(stats).to have_key(:total_amount)
        expect(stats).to have_key(:active_rules)
        expect(stats).to have_key(:unresolved_anomalies)
        expect(stats).to have_key(:categories_count)
        expect(stats).to have_key(:monthly_trends)
        expect(stats).to have_key(:category_breakdown)
      end

      it 'uses caching for expensive calculations' do
        # Test that individual cache keys are used
        allow(Rails.cache).to receive(:fetch).and_call_original
        expect(Rails.cache).to receive(:fetch).with("total_transactions_count", expires_in: 10.minutes).and_call_original
        expect(Rails.cache).to receive(:fetch).with("total_amount_sum", expires_in: 10.minutes).and_call_original
        expect(Rails.cache).to receive(:fetch).with("active_rules_count", expires_in: 30.minutes).and_call_original

        controller_instance.send(:calculate_statistics)
      end
    end

    describe '#calculate_monthly_trends' do
      it 'returns monthly transaction trends grouped by status' do
        trends = controller_instance.send(:calculate_monthly_trends)

        expect(trends).to be_a(Hash)
      end
    end

    describe '#calculate_category_breakdown' do
      it 'returns category statistics' do
        breakdown = controller_instance.send(:calculate_category_breakdown)

        expect(breakdown).to be_an(Array)
        expect(breakdown.first).to have_key(:category)
        expect(breakdown.first).to have_key(:count)
        expect(breakdown.first).to have_key(:total_amount)
      end
    end

    describe '#transaction_json' do
      let(:transaction) { transactions.first }

      it 'returns formatted transaction data' do
        json_data = controller_instance.send(:transaction_json, transaction)

        expect(json_data).to have_key(:id)
        expect(json_data).to have_key(:amount)
        expect(json_data).to have_key(:description)
        expect(json_data).to have_key(:transaction_date)
        expect(json_data).to have_key(:status)
        expect(json_data).to have_key(:category)
        expect(json_data).to have_key(:anomaly_count)
      end

      it 'includes anomaly count' do
        json_data = controller_instance.send(:transaction_json, transaction)

        expect(json_data[:anomaly_count]).to eq(1) # Has one anomaly
      end
    end

    describe '#anomaly_json' do
      it 'returns formatted anomaly data' do
        json_data = controller_instance.send(:anomaly_json, anomaly)

        expect(json_data).to have_key(:id)
        expect(json_data).to have_key(:type)
        expect(json_data).to have_key(:severity)
        expect(json_data).to have_key(:severity_label)
        expect(json_data).to have_key(:description)
        expect(json_data).to have_key(:transaction_id)
        expect(json_data).to have_key(:detected_at)
      end

      it 'includes transaction reference' do
        json_data = controller_instance.send(:anomaly_json, anomaly)

        expect(json_data[:transaction_id]).to eq(anomaly.transaction_record_id)
      end
    end
  end

  describe 'caching behavior' do
    it 'uses different cache keys for different endpoints' do
      expect(Rails.cache).to receive(:fetch).with("dashboard_statistics", expires_in: 5.minutes)
      expect(Rails.cache).to receive(:fetch).with("recent_transactions", expires_in: 1.minute)
      expect(Rails.cache).to receive(:fetch).with("active_anomalies", expires_in: 2.minutes)

      get :statistics
      get :recent_transactions
      get :active_anomalies
    end

    it 'serves cached data on subsequent requests' do
      # First request
      get :statistics
      first_response = JSON.parse(response.body)

      # Second request should return the same data due to caching
      get :statistics
      second_response = JSON.parse(response.body)

      expect(first_response).to eq(second_response)
    end
  end
end
