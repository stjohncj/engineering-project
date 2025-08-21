require 'rails_helper'

RSpec.describe Api::V1::AnomalyDetectionsController, type: :controller do
  let(:transaction) { create(:transaction) }
  let(:valid_attributes) do
    {
      transaction_record_id: transaction.id,
      anomaly_type: 'unusual_amount',
      description: 'Test anomaly',
      severity: 3,
      metadata: { test: 'data' }
    }
  end

  let(:invalid_attributes) do
    {
      transaction_record_id: nil,
      anomaly_type: '',
      description: '',
      severity: 10
    }
  end

  describe 'GET #index' do
    let!(:anomalies) { create_list(:anomaly_detection, 5) }
    let!(:resolved_anomaly) { create(:anomaly_detection, :resolved) }

    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end

    it 'returns all anomalies by default' do
      get :index
      json = JSON.parse(response.body)
      expect(json['anomaly_detections'].length).to eq(6)
    end

    it 'includes pagination metadata' do
      get :index
      json = JSON.parse(response.body)
      expect(json).to have_key('pagination')
      expect(json['pagination']).to include('current_page', 'per_page', 'total_count')
    end

    it 'ensures total_count is never zero when anomalies exist' do
      # This test catches the pagination bug we just fixed
      get :index, params: { per_page: 3 }
      json = JSON.parse(response.body)
      expect(json['pagination']['total_count']).to be > 0
      expect(json['pagination']['total_count']).to eq(AnomalyDetection.count)
    end

    it 'handles unpermitted parameters gracefully' do
      # This test catches ActionController::UnfilteredParameters errors
      get :index, params: {
        malicious_param: 'hack_attempt',
        unresolved: 'true',
        bad_nested: { param: 'value' }
      }
      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json).to have_key('anomaly_detections')
      expect(json).to have_key('pagination')
    end

    it 'calculates pagination correctly with filters' do
      # Test pagination with the unresolved filter that was causing issues
      unresolved_count = AnomalyDetection.where(resolved: false).count
      get :index, params: { unresolved: 'true', per_page: 2 }
      json = JSON.parse(response.body)
      expect(json['pagination']['total_count']).to eq(unresolved_count)
      expected_pages = (unresolved_count.to_f / 2).ceil
      expect(json['pagination']['total_pages']).to eq(expected_pages)
    end

    context 'filtering by resolution status' do
      it 'returns only unresolved anomalies when requested' do
        get :index, params: { unresolved: true }
        json = JSON.parse(response.body)
        expect(json['anomaly_detections'].length).to eq(5)
        expect(json['anomaly_detections'].none? { |a| a['resolved'] }).to be true
      end

      it 'returns only resolved anomalies when requested' do
        get :index, params: { resolved: true }
        json = JSON.parse(response.body)
        expect(json['anomaly_detections'].length).to eq(1)
        expect(json['anomaly_detections'].all? { |a| a['resolved'] }).to be true
      end
    end

    context 'filtering by severity' do
      let!(:high_severity) { create(:anomaly_detection, :high_severity) }
      let!(:low_severity) { create(:anomaly_detection, :low_severity) }

      it 'filters by minimum severity' do
        get :index, params: { min_severity: 4 }
        json = JSON.parse(response.body)
        severities = json['anomaly_detections'].map { |a| a['severity'] }
        expect(severities.all? { |s| s >= 4 }).to be true
      end

      it 'filters by maximum severity' do
        get :index, params: { max_severity: 2 }
        json = JSON.parse(response.body)
        severities = json['anomaly_detections'].map { |a| a['severity'] }
        expect(severities.all? { |s| s <= 2 }).to be true
      end
    end

    context 'filtering by anomaly type' do
      let!(:duplicate_anomaly) { create(:anomaly_detection, :potential_duplicate) }
      let!(:incomplete_anomaly) { create(:anomaly_detection, :incomplete_data) }

      it 'filters by anomaly type' do
        get :index, params: { anomaly_type: 'potential_duplicate' }
        json = JSON.parse(response.body)
        types = json['anomaly_detections'].map { |a| a['anomaly_type'] }.uniq
        expect(types).to eq([ 'potential_duplicate' ])
      end
    end

    context 'ordering' do
      before do
        create(:anomaly_detection, severity: 5, detected_at: 1.hour.ago)
        create(:anomaly_detection, severity: 1, detected_at: 2.hours.ago)
        create(:anomaly_detection, severity: 3, detected_at: 30.minutes.ago)
      end

      it 'orders by severity descending by default' do
        get :index, params: { per_page: 100 } # Get all results
        json = JSON.parse(response.body)
        severities = json['anomaly_detections'].map { |a| a['severity'] }
        expect(severities).to eq(severities.sort.reverse)
      end

      it 'can order by detected_at descending' do
        get :index, params: { order_by: 'detected_at', per_page: 100 }
        json = JSON.parse(response.body)
        times = json['anomaly_detections'].map { |a| Time.parse(a['detected_at']) }
        expect(times).to eq(times.sort.reverse)
      end
    end
  end

  describe 'GET #show' do
    let!(:anomaly) { create(:anomaly_detection) }

    it 'returns a success response' do
      get :show, params: { id: anomaly.to_param }
      expect(response).to be_successful
    end

    it 'returns the anomaly' do
      get :show, params: { id: anomaly.to_param }
      json = JSON.parse(response.body)
      expect(json['anomaly_detection']['id']).to eq(anomaly.id)
    end

    it 'includes associated transaction data' do
      get :show, params: { id: anomaly.to_param }
      json = JSON.parse(response.body)
      expect(json['anomaly_detection']['transaction']).to be_present
      expect(json['anomaly_detection']['transaction']['id']).to eq(anomaly.transaction.id)
    end

    it 'includes severity label' do
      get :show, params: { id: anomaly.to_param }
      json = JSON.parse(response.body)
      expect(json['anomaly_detection']['severity_label']).to be_present
    end

    it 'returns 404 for non-existent anomaly' do
      get :show, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new AnomalyDetection' do
        expect {
          post :create, params: { anomaly_detection: valid_attributes }
        }.to change(AnomalyDetection, :count).by(1)
      end

      it 'returns a created response' do
        post :create, params: { anomaly_detection: valid_attributes }
        expect(response).to have_http_status(:created)
      end

      it 'returns the created anomaly' do
        post :create, params: { anomaly_detection: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['anomaly_detection']['anomaly_type']).to eq('unusual_amount')
        expect(json['anomaly_detection']['severity']).to eq(3)
      end

      it 'sets detected_at to current time' do
        post :create, params: { anomaly_detection: valid_attributes }
        json = JSON.parse(response.body)
        detected_at = Time.parse(json['anomaly_detection']['detected_at'])
        expect(detected_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new AnomalyDetection' do
        expect {
          post :create, params: { anomaly_detection: invalid_attributes }
        }.not_to change(AnomalyDetection, :count)
      end

      it 'returns an unprocessable entity response' do
        post :create, params: { anomaly_detection: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error messages' do
        post :create, params: { anomaly_detection: invalid_attributes }
        json = JSON.parse(response.body)
        expect(json).to have_key('errors')
      end
    end
  end

  describe 'PATCH #update' do
    let!(:anomaly) { create(:anomaly_detection) }

    context 'with valid parameters' do
      let(:new_attributes) { { description: 'Updated description', severity: 4 } }

      it 'updates the anomaly' do
        patch :update, params: { id: anomaly.to_param, anomaly_detection: new_attributes }
        anomaly.reload
        expect(anomaly.description).to eq('Updated description')
        expect(anomaly.severity).to eq(4)
      end

      it 'returns a success response' do
        patch :update, params: { id: anomaly.to_param, anomaly_detection: new_attributes }
        expect(response).to be_successful
      end
    end

    context 'with invalid parameters' do
      it 'returns an unprocessable entity response' do
        patch :update, params: { id: anomaly.to_param, anomaly_detection: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH #resolve' do
    let!(:unresolved_anomaly) { create(:anomaly_detection, resolved: false) }

    it 'marks the anomaly as resolved' do
      patch :resolve, params: { id: unresolved_anomaly.to_param }
      unresolved_anomaly.reload
      expect(unresolved_anomaly.resolved).to be true
    end

    it 'sets resolved_at timestamp' do
      patch :resolve, params: { id: unresolved_anomaly.to_param }
      unresolved_anomaly.reload
      expect(unresolved_anomaly.resolved_at).to be_within(1.second).of(Time.current)
    end

    it 'returns a success response' do
      patch :resolve, params: { id: unresolved_anomaly.to_param }
      expect(response).to be_successful
    end

    it 'returns the updated anomaly' do
      patch :resolve, params: { id: unresolved_anomaly.to_param }
      json = JSON.parse(response.body)
      expect(json['anomaly_detection']['resolved']).to be true
      expect(json['anomaly_detection']['resolved_at']).to be_present
    end

    context 'with already resolved anomaly' do
      let!(:resolved_anomaly) { create(:anomaly_detection, :resolved) }

      it 'does not change resolved_at timestamp' do
        original_time = resolved_anomaly.resolved_at
        patch :resolve, params: { id: resolved_anomaly.to_param }
        resolved_anomaly.reload
        expect(resolved_anomaly.resolved_at).to be_within(1.second).of(original_time)
      end
    end

    it 'returns 404 for non-existent anomaly' do
      patch :resolve, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE #destroy' do
    let!(:anomaly) { create(:anomaly_detection) }

    it 'destroys the requested anomaly' do
      expect {
        delete :destroy, params: { id: anomaly.to_param }
      }.to change(AnomalyDetection, :count).by(-1)
    end

    it 'returns no content response' do
      delete :destroy, params: { id: anomaly.to_param }
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 404 for non-existent anomaly' do
      delete :destroy, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'statistics and aggregations' do
    before do
      create_list(:anomaly_detection, 3, severity: 5, anomaly_type: 'unusual_amount')
      create_list(:anomaly_detection, 2, severity: 3, anomaly_type: 'potential_duplicate')
      create(:anomaly_detection, :resolved, severity: 4)
    end

    context 'summary statistics' do
      it 'includes count of unresolved anomalies' do
        get :index, params: { unresolved: true }
        json = JSON.parse(response.body)
        expect(json['pagination']['total_count']).to eq(5)
      end

      it 'groups by anomaly type when requested' do
        # This would require additional controller action or parameter
        # For now, we can test that the data is available for grouping
        get :index, params: { per_page: 100 }
        json = JSON.parse(response.body)
        types = json['anomaly_detections'].group_by { |a| a['anomaly_type'] }
        expect(types.keys).to include('unusual_amount', 'potential_duplicate')
      end
    end
  end

  describe 'JSON serialization' do
    let!(:anomaly) { create(:anomaly_detection, metadata: { key: 'value', number: 42 }) }

    it 'properly serializes metadata' do
      get :show, params: { id: anomaly.to_param }
      json = JSON.parse(response.body)
      expect(json['anomaly_detection']['metadata']).to eq({ 'key' => 'value', 'number' => 42 })
    end

    it 'includes all required fields' do
      get :show, params: { id: anomaly.to_param }
      json = JSON.parse(response.body)
      anomaly_data = json['anomaly_detection']

      expected_fields = %w[id anomaly_type description severity severity_label resolved detected_at metadata transaction]
      expect(anomaly_data.keys).to include(*expected_fields)
    end
  end
end
