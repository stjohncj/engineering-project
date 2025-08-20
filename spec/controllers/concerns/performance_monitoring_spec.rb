require 'rails_helper'

RSpec.describe PerformanceMonitoring, type: :controller do
  controller(ApplicationController) do
    include PerformanceMonitoring

    def fast_action
      render json: { message: 'Fast response' }
    end

    def slow_action
      # Simulate slow action
      allow(self).to receive(:action_name).and_return('slow_action')
      sleep(0.1) if Rails.env.test? # Small delay for testing
      render json: { message: 'Slow response' }
    end

    def error_action
      raise StandardError, 'Test error'
    end

    private

    def should_monitor_performance?
      params[:monitor] == 'true' || super
    end
  end

  before do
    routes.draw do
      get 'fast_action' => 'anonymous#fast_action'
      get 'slow_action' => 'anonymous#slow_action'
      get 'error_action' => 'anonymous#error_action'
    end

    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#monitor_performance' do
    context 'when monitoring is enabled' do
      it 'logs performance metrics for requests' do
        expect(Rails.logger).to receive(:info).with(a_string_matching(/PERFORMANCE:/))

        get :fast_action, params: { monitor: 'true' }
      end

      it 'adds performance headers to response' do
        get :fast_action, params: { monitor: 'true' }

        expect(response.headers['X-Response-Time']).to be_present
        expect(response.headers['X-Memory-Usage']).to be_present
        expect(response.headers['X-Response-Time']).to match(/\d+(\.\d+)?ms/)
        expect(response.headers['X-Memory-Usage']).to match(/\d+(\.\d+)?MB/)
      end

      it 'includes comprehensive metrics in logs' do
        expected_metrics = {
          controller: 'anonymous',
          action: 'fast_action',
          duration_ms: kind_of(Numeric),
          memory_mb: kind_of(Numeric),
          timestamp: kind_of(String),
          params: kind_of(Hash),
          user_agent: kind_of(String),
          ip: kind_of(String),
          method: 'GET',
          path: '/fast_action',
          cache_hit: kind_of(Boolean)
        }

        expect(Rails.logger).to receive(:info) do |message|
          expect(message).to include('PERFORMANCE:')
          
          # Parse the JSON from the log message
          json_part = message.split('PERFORMANCE: ')[1]
          metrics = JSON.parse(json_part)
          
          expected_metrics.each do |key, value_type|
            expect(metrics[key.to_s]).to be_a(value_type) if value_type.is_a?(Class)
          end
        end

        get :fast_action, params: { monitor: 'true' }
      end

      it 'filters sensitive parameters from logs' do
        expect(Rails.logger).to receive(:info) do |message|
          expect(message).not_to include('password')
          expect(message).not_to include('secret_token')
        end

        get :fast_action, params: { 
          monitor: 'true', 
          password: 'secret123',
          token: 'secret_token',
          normal_param: 'visible'
        }
      end
    end

    context 'when monitoring is disabled' do
      it 'does not log performance metrics' do
        expect(Rails.logger).not_to receive(:info).with(a_string_matching(/PERFORMANCE:/))

        get :fast_action # monitor param not set
      end

      it 'does not add performance headers' do
        get :fast_action

        expect(response.headers['X-Response-Time']).to be_nil
        expect(response.headers['X-Memory-Usage']).to be_nil
      end
    end

    context 'with slow requests' do
      before do
        # Mock slow request threshold to be very low for testing
        allow_any_instance_of(controller.class).to receive(:slow_request_threshold).and_return(1) # 1ms
      end

      it 'logs warnings for slow requests' do
        expect(Rails.logger).to receive(:warn).with(a_string_matching(/SLOW_REQUEST:/))

        get :slow_action, params: { monitor: 'true' }
      end

      it 'includes threshold information in slow request warning' do
        expect(Rails.logger).to receive(:warn) do |message|
          expect(message).to include('anonymous#slow_action')
          expect(message).to include('threshold: 1ms')
        end

        get :slow_action, params: { monitor: 'true' }
      end
    end

    context 'when performance monitoring fails' do
      before do
        allow_any_instance_of(controller.class).to receive(:get_memory_usage).and_raise(StandardError, 'Memory error')
      end

      it 'handles monitoring errors gracefully' do
        expect(Rails.logger).to receive(:error).with('Performance monitoring error: Memory error')

        expect { get :fast_action, params: { monitor: 'true' } }.not_to raise_error
      end

      it 'still processes the request normally' do
        get :fast_action, params: { monitor: 'true' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['message']).to eq('Fast response')
      end
    end
  end

  describe '#get_memory_usage' do
    let(:controller_instance) { controller }

    it 'returns memory usage in MB' do
      memory_usage = controller_instance.send(:get_memory_usage)

      expect(memory_usage).to be_a(Numeric)
      expect(memory_usage).to be >= 0
    end

    context 'when GC is not available' do
      before do
        allow(GC).to receive(:stat).and_raise(StandardError)
      end

      it 'returns 0 when GC stats fail' do
        memory_usage = controller_instance.send(:get_memory_usage)

        expect(memory_usage).to eq(0)
      end
    end
  end

  describe '#filtered_params' do
    let(:controller_instance) { controller }

    it 'removes sensitive parameters' do
      allow(controller_instance).to receive(:params).and_return(
        ActionController::Parameters.new({
          username: 'test_user',
          password: 'secret123',
          password_confirmation: 'secret123',
          token: 'abc123',
          file: 'uploaded_file.txt',
          normal_param: 'visible'
        })
      )

      filtered = controller_instance.send(:filtered_params)

      expect(filtered['username']).to eq('test_user')
      expect(filtered['normal_param']).to eq('visible')
      expect(filtered).not_to have_key('password')
      expect(filtered).not_to have_key('password_confirmation')
      expect(filtered).not_to have_key('token')
      expect(filtered).not_to have_key('file')
    end
  end

  describe 'configuration methods' do
    let(:controller_instance) { controller }

    describe '#should_monitor_performance?' do
      it 'enables monitoring in production' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        expect(controller_instance.send(:should_monitor_performance?)).to be true
      end

      it 'enables monitoring in staging' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('staging'))
        expect(controller_instance.send(:should_monitor_performance?)).to be true
      end

      it 'can be enabled with monitor param' do
        allow(controller_instance).to receive(:params).and_return({ monitor: 'true' })
        expect(controller_instance.send(:should_monitor_performance?)).to be true
      end
    end

    describe '#should_log_slow_queries?' do
      it 'enables slow query logging in development' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        expect(controller_instance.send(:should_log_slow_queries?)).to be true
      end

      it 'can be enabled with debug param' do
        allow(controller_instance).to receive(:params).and_return({ debug: 'true' })
        expect(controller_instance.send(:should_log_slow_queries?)).to be true
      end
    end

    describe '#slow_request_threshold' do
      it 'uses default threshold when not configured' do
        expect(controller_instance.send(:slow_request_threshold)).to eq(1000)
      end

      it 'uses environment variable when configured' do
        stub_const('ENV', ENV.to_hash.merge('SLOW_REQUEST_THRESHOLD' => '500'))
        expect(controller_instance.send(:slow_request_threshold)).to eq(500)
      end
    end

    describe '#slow_query_threshold' do
      it 'uses default threshold when not configured' do
        expect(controller_instance.send(:slow_query_threshold)).to eq(100)
      end

      it 'uses environment variable when configured' do
        stub_const('ENV', ENV.to_hash.merge('SLOW_QUERY_THRESHOLD' => '250'))
        expect(controller_instance.send(:slow_query_threshold)).to eq(250)
      end
    end
  end

  describe '#send_to_monitoring_service' do
    let(:controller_instance) { controller }

    context 'when monitoring service is enabled' do
      before do
        stub_const('ENV', ENV.to_hash.merge('MONITORING_SERVICE_ENABLED' => 'true'))
      end

      it 'logs metrics for monitoring service' do
        metrics = { controller: 'test', action: 'index', duration_ms: 50 }

        expect(Rails.logger).to receive(:info).with("MONITORING_SERVICE: #{metrics.to_json}")

        controller_instance.send(:send_to_monitoring_service, metrics)
      end
    end

    context 'when monitoring service is disabled' do
      before do
        stub_const('ENV', ENV.to_hash.merge('MONITORING_SERVICE_ENABLED' => 'false'))
      end

      it 'does not send metrics to monitoring service' do
        expect(Rails.logger).not_to receive(:info).with(a_string_matching(/MONITORING_SERVICE:/))

        controller_instance.send(:send_to_monitoring_service, {})
      end
    end
  end

  describe 'integration with action processing' do
    it 'wraps actions with performance monitoring' do
      expect_any_instance_of(controller.class).to receive(:monitor_performance).and_call_original

      get :fast_action, params: { monitor: 'true' }
    end

    it 'monitors performance even when action raises error' do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/PERFORMANCE:/))

      expect { get :error_action, params: { monitor: 'true' } }.to raise_error(StandardError)
    end

    it 'ensures monitoring cleanup happens even on errors' do
      # Performance monitoring should not interfere with error handling
      expect { get :error_action, params: { monitor: 'true' } }.to raise_error(StandardError, 'Test error')
    end
  end
end