class Api::V1::PerformanceController < ApplicationController
  # Performance and health check endpoints

  def health
    # Basic health check for load balancers
    render json: {
      status: "healthy",
      timestamp: Time.current.iso8601,
      version: Rails.application.class.module_parent_name,
      environment: Rails.env
    }
  end

  def metrics
    # Return system performance metrics
    metrics = Rails.cache.fetch("system_metrics", expires_in: 1.minute) do
      calculate_system_metrics
    end

    render json: {
      metrics: metrics,
      timestamp: Time.current.iso8601
    }
  end

  def database_stats
    # Database performance statistics
    stats = Rails.cache.fetch("database_stats", expires_in: 5.minutes) do
      calculate_database_stats
    end

    render json: {
      database: stats,
      timestamp: Time.current.iso8601
    }
  end

  def cache_stats
    # Cache performance statistics
    if Rails.cache.respond_to?(:stats)
      cache_stats = Rails.cache.stats
    else
      cache_stats = { message: "Cache stats not available for this cache store" }
    end

    render json: {
      cache: cache_stats,
      timestamp: Time.current.iso8601
    }
  end

  private

  def calculate_system_metrics
    {
      memory_usage: get_memory_usage,
      gc_stats: GC.stat,
      object_count: ObjectSpace.count_objects,
      uptime: (Time.current - Time.current.beginning_of_day).to_i,
      ruby_version: RUBY_VERSION,
      rails_version: Rails.version
    }
  rescue => e
    { error: "Unable to collect system metrics: #{e.message}" }
  end

  def calculate_database_stats
    {
      connection_pool: {
        size: ActiveRecord::Base.connection_pool.size,
        checked_out: ActiveRecord::Base.connection_pool.checked_out.size,
        available: ActiveRecord::Base.connection_pool.available.size
      },
      table_counts: {
        transactions: Transaction.count,
        categories: Category.count,
        rules: Rule.count,
        anomaly_detections: AnomalyDetection.count
      },
      largest_tables: get_table_sizes,
      slow_queries: get_recent_slow_queries
    }
  rescue => e
    { error: "Unable to collect database stats: #{e.message}" }
  end

  def get_memory_usage
    # Get memory usage in MB using GC stats
    gc_stats = GC.stat
    if gc_stats[:heap_live_slots] && gc_stats[:heap_allocated_slots]
      # Use allocated slots as a proxy for memory usage
      memory_mb = (gc_stats[:heap_allocated_slots] * 40 / 1024.0 / 1024.0).round(2)
      [memory_mb, 1.0].max # Minimum 1MB
    else
      1.0 # Default fallback
    end
  rescue
    1.0
  end

  def get_table_sizes
    # PostgreSQL specific query to get table sizes
    return {} unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"

    query = <<-SQL
      SELECT#{' '}
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        pg_total_relation_size(schemaname||'.'||tablename) as size_bytes
      FROM pg_tables#{' '}
      WHERE schemaname = 'public'
      ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC#{' '}
      LIMIT 10
    SQL

    ActiveRecord::Base.connection.exec_query(query).to_a
  rescue => e
    { error: "Unable to get table sizes: #{e.message}" }
  end

  def get_recent_slow_queries
    # This would need to be implemented based on your query logging setup
    # For now, return placeholder
    { message: "Slow query tracking not implemented" }
  end
end
