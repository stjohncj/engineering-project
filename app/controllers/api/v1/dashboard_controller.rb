class Api::V1::DashboardController < ApplicationController
  # Cache statistics for 5 minutes since they don't change frequently
  STATS_CACHE_DURATION = 5.minutes

  def statistics
    # Use Rails cache to store expensive statistics calculations
    stats = Rails.cache.fetch("dashboard_statistics", expires_in: STATS_CACHE_DURATION) do
      calculate_statistics
    end

    render json: { statistics: stats }
  end

  def recent_transactions
    # Cache recent transactions for 1 minute
    transactions = Rails.cache.fetch("recent_transactions", expires_in: 1.minute) do
      Transaction.includes(:category, :anomaly_detections)
                 .order(created_at: :desc)
                 .limit(10)
                 .map { |t| transaction_json(t) }
    end

    render json: { transactions: transactions }
  end

  def active_anomalies
    # Cache active anomalies for 2 minutes
    anomalies = Rails.cache.fetch("active_anomalies", expires_in: 2.minutes) do
      AnomalyDetection.unresolved
                      .includes(:transaction_record)
                      .order(severity: :desc, created_at: :desc)
                      .limit(5)
                      .map { |a| anomaly_json(a) }
    end

    render json: { anomalies: anomalies }
  end

  private

  def calculate_statistics
    # Use efficient database queries with proper indexing
    {
      total_transactions: Rails.cache.fetch("total_transactions_count", expires_in: 10.minutes) do
        Transaction.count
      end,
      total_amount: Rails.cache.fetch("total_amount_sum", expires_in: 10.minutes) do
        Transaction.sum(:amount).to_f
      end,
      active_rules: Rails.cache.fetch("active_rules_count", expires_in: 30.minutes) do
        Rule.where(active: true).count
      end,
      unresolved_anomalies: Rails.cache.fetch("unresolved_anomalies_count", expires_in: 5.minutes) do
        AnomalyDetection.where(resolved: false).count
      end,
      categories_count: Rails.cache.fetch("categories_count", expires_in: 1.hour) do
        Category.count
      end,
      # Monthly transaction trends (cached for 1 hour)
      monthly_trends: Rails.cache.fetch("monthly_transaction_trends", expires_in: 1.hour) do
        calculate_monthly_trends
      end,
      # Category breakdown (cached for 30 minutes)
      category_breakdown: Rails.cache.fetch("category_breakdown", expires_in: 30.minutes) do
        calculate_category_breakdown
      end
    }
  end

  def calculate_monthly_trends
    # Efficient query using SQL GROUP BY with proper indexing on transaction_date
    Transaction.group("DATE_TRUNC('month', transaction_date)")
               .group(:status)
               .count
               .transform_keys { |k| k.is_a?(Array) ? { month: k[0], status: k[1] } : k }
  end

  def calculate_category_breakdown
    # Use joins and group to efficiently calculate category statistics
    Transaction.joins(:category)
               .group("categories.name")
               .select("categories.name, COUNT(*) as transaction_count, SUM(amount) as total_amount")
               .map do |result|
                 {
                   category: result.name,
                   count: result.transaction_count,
                   total_amount: result.total_amount.to_f
                 }
               end
  end

  def transaction_json(transaction)
    {
      id: transaction.id,
      amount: transaction.amount.to_f,
      description: transaction.description,
      transaction_date: transaction.transaction_date,
      status: transaction.status,
      category: transaction.category&.name,
      anomaly_count: transaction.anomaly_detections.count,
      anomalies: transaction.anomaly_detections.unresolved.map { |a|
        {
          id: a.id,
          type: a.anomaly_type,
          severity: a.severity
        }
      }
    }
  end

  def anomaly_json(anomaly)
    {
      id: anomaly.id,
      type: anomaly.anomaly_type,
      severity: anomaly.severity,
      severity_label: anomaly.severity_label,
      description: anomaly.description,
      transaction_id: anomaly.transaction_record_id,
      detected_at: anomaly.detected_at
    }
  end
end
