module PerformanceMonitoring
  extend ActiveSupport::Concern
  
  included do
    around_action :monitor_performance, if: -> { should_monitor_performance? }
    after_action :log_slow_queries, if: -> { should_log_slow_queries? }
  end
  
  private
  
  def monitor_performance
    start_time = Time.current
    start_memory = get_memory_usage
    
    yield
    
    end_time = Time.current
    end_memory = get_memory_usage
    
    duration = ((end_time - start_time) * 1000).round(2) # Convert to milliseconds
    memory_used = end_memory - start_memory
    
    # Log performance metrics
    log_performance_metrics(duration, memory_used, start_time)
    
    # Add performance headers to response
    add_performance_headers(duration, memory_used)
    
    # Alert on slow requests
    alert_on_slow_request(duration) if duration > slow_request_threshold
    
  rescue => e
    Rails.logger.error "Performance monitoring error: #{e.message}"
    yield
  end
  
  def log_performance_metrics(duration, memory_used, start_time)
    metrics = {
      controller: controller_name,
      action: action_name,
      duration_ms: duration,
      memory_mb: memory_used,
      timestamp: start_time.iso8601,
      params: filtered_params,
      user_agent: request.user_agent,
      ip: request.remote_ip,
      method: request.method,
      path: request.path,
      cache_hit: response.headers['X-Cache-Status'] == 'HIT'
    }
    
    # Log to Rails logger
    Rails.logger.info "PERFORMANCE: #{metrics.to_json}"
    
    # Send to performance monitoring service (if configured)
    send_to_monitoring_service(metrics) if monitoring_service_enabled?
  end
  
  def add_performance_headers(duration, memory_used)
    response.headers['X-Response-Time'] = "#{duration}ms"
    response.headers['X-Memory-Usage'] = "#{memory_used}MB"
    response.headers['X-Query-Count'] = query_count.to_s if respond_to?(:query_count)
  end
  
  def log_slow_queries
    # Log queries that took longer than threshold
    if defined?(ActiveRecord::Base)
      slow_queries = Thread.current[:ar_query_log]&.select { |q| q[:duration] > slow_query_threshold }
      
      if slow_queries&.any?
        Rails.logger.warn "SLOW_QUERIES: #{slow_queries.to_json}"
      end
    end
  end
  
  def alert_on_slow_request(duration)
    Rails.logger.warn "SLOW_REQUEST: #{controller_name}##{action_name} took #{duration}ms (threshold: #{slow_request_threshold}ms)"
    
    # Could integrate with monitoring services like New Relic, DataDog, etc.
    # NewRelic::Agent.notice_error("Slow request: #{duration}ms") if defined?(NewRelic)
  end
  
  def get_memory_usage
    # Get current memory usage in MB
    if defined?(GC)
      GC.stat[:heap_live_slots] * GC::INTERNAL_CONSTANTS[:RVALUE_SIZE] / 1024.0 / 1024.0
    else
      0
    end
  rescue
    0
  end
  
  def filtered_params
    # Remove sensitive parameters for logging
    params.except(:password, :password_confirmation, :token, :file).to_unsafe_h
  end
  
  def should_monitor_performance?
    # Enable performance monitoring based on environment or configuration
    Rails.env.production? || Rails.env.staging? || params[:monitor] == 'true'
  end
  
  def should_log_slow_queries?
    Rails.env.development? || params[:debug] == 'true'
  end
  
  def monitoring_service_enabled?
    # Check if external monitoring service is configured
    ENV['MONITORING_SERVICE_ENABLED'] == 'true'
  end
  
  def send_to_monitoring_service(metrics)
    # Placeholder for external monitoring service integration
    # Could integrate with DataDog, New Relic, CloudWatch, etc.
    Rails.logger.info "MONITORING_SERVICE: #{metrics.to_json}"
  end
  
  def slow_request_threshold
    # Configurable threshold for slow requests (in milliseconds)
    (ENV['SLOW_REQUEST_THRESHOLD'] || 1000).to_i
  end
  
  def slow_query_threshold
    # Configurable threshold for slow queries (in milliseconds)
    (ENV['SLOW_QUERY_THRESHOLD'] || 100).to_i
  end
end