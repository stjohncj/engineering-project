module QueryCounter
  extend ActiveSupport::Concern

  included do
    around_action :count_queries, if: -> { should_count_queries? }
  end

  private

  def count_queries
    queries_before = query_count_start

    yield

    queries_after = query_count_end
    total_queries = queries_after - queries_before

    # Add query count to response headers
    response.headers["X-Query-Count"] = total_queries.to_s

    # Log warning for potential N+1 queries
    if total_queries > query_warning_threshold
      Rails.logger.warn "HIGH_QUERY_COUNT: #{controller_name}##{action_name} executed #{total_queries} queries (threshold: #{query_warning_threshold})"
      log_query_details if Rails.env.development?
    end

  rescue => e
    Rails.logger.error "Query counting error: #{e.message}"
    yield
  ensure
    # Clean up thread-local storage
    Thread.current[:query_count] = nil
    Thread.current[:ar_query_log] = nil
  end

  def query_count_start
    Thread.current[:query_count] = 0
    Thread.current[:ar_query_log] = []

    # Subscribe to ActiveRecord query notifications
    @query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
      # Skip schema queries and cached queries
      unless payload[:name] =~ /^(SCHEMA|CACHE)/
        Thread.current[:query_count] += 1

        # Store query details for debugging
        Thread.current[:ar_query_log] << {
          sql: payload[:sql],
          duration: (finish - start) * 1000, # Convert to milliseconds
          name: payload[:name],
          timestamp: start
        }
      end
    end

    0
  end

  def query_count_end
    # Unsubscribe from notifications
    ActiveSupport::Notifications.unsubscribe(@query_subscriber) if @query_subscriber

    Thread.current[:query_count] || 0
  end

  def log_query_details
    queries = Thread.current[:ar_query_log] || []

    Rails.logger.debug "QUERY_DETAILS for #{controller_name}##{action_name}:"
    queries.each_with_index do |query, index|
      Rails.logger.debug "  #{index + 1}. [#{query[:duration].round(2)}ms] #{query[:name]}: #{query[:sql].truncate(200)}"
    end
  end

  def should_count_queries?
    Rails.env.development? || Rails.env.test? || params[:count_queries] == "true"
  end

  def query_warning_threshold
    (ENV["QUERY_WARNING_THRESHOLD"] || 10).to_i
  end
end
