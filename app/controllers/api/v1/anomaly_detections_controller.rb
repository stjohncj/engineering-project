class Api::V1::AnomalyDetectionsController < ApplicationController
  include Paginatable

  before_action :set_anomaly_detection, only: [ :show, :update, :destroy, :resolve ]

  def index
    # Build query with eager loading
    @anomaly_detections = AnomalyDetection.includes(transaction_record: :category)

    # Apply filters efficiently
    @anomaly_detections = @anomaly_detections.where(resolved: false) if params[:unresolved] == "true"
    @anomaly_detections = @anomaly_detections.where(resolved: true) if params[:resolved] == "true"
    @anomaly_detections = @anomaly_detections.by_severity(params[:severity]) if params[:severity].present?
    @anomaly_detections = @anomaly_detections.where("severity >= ?", params[:min_severity]) if params[:min_severity].present?
    @anomaly_detections = @anomaly_detections.where("severity <= ?", params[:max_severity]) if params[:max_severity].present?
    @anomaly_detections = @anomaly_detections.by_type(params[:anomaly_type]) if params[:anomaly_type].present?

    # Order by priority (severity desc, then creation time) unless otherwise specified
    if params[:order_by] == "detected_at"
      @anomaly_detections = @anomaly_detections.order(detected_at: :desc, created_at: :desc)
    else
      @anomaly_detections = @anomaly_detections.order(severity: :desc, created_at: :desc)
    end

    # Get current page and per_page params
    page = params[:page]&.to_i || 1
    per_page = [ (params[:per_page]&.to_i || 50), 100 ].min

    # Use Kaminari for pagination
    paginated_anomalies = @anomaly_detections.page(page).per(per_page)

    # Get total count manually to ensure accuracy
    total_count = @anomaly_detections.except(:limit, :offset, :order).count
    total_pages = (total_count.to_f / per_page).ceil

    # Convert to JSON
    anomaly_data = paginated_anomalies.map { |ad| anomaly_detection_json(ad) }

    # Build pagination info manually
    pagination_info = {
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      next_page: page < total_pages ? page + 1 : nil,
      prev_page: page > 1 ? page - 1 : nil
    }

    # Build response
    result = {
      anomaly_detections: anomaly_data,
      pagination: pagination_info
    }

    expires_in 3.minutes, public: true
    render json: result
  end

  def show
    render json: { anomaly_detection: anomaly_detection_json(@anomaly_detection, include_transaction: true) }
  end

  def create
    @anomaly_detection = AnomalyDetection.new(anomaly_detection_params)
    @anomaly_detection.detected_at = Time.current

    if @anomaly_detection.save
      # Invalidate relevant caches
      invalidate_anomaly_caches

      render json: { anomaly_detection: anomaly_detection_json(@anomaly_detection) }, status: :created
    else
      render json: { errors: @anomaly_detection.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @anomaly_detection.update(anomaly_detection_params)
      render json: { anomaly_detection: anomaly_detection_json(@anomaly_detection) }
    else
      render json: { errors: @anomaly_detection.errors.full_messages }, status: :unprocessable_content
    end
  end

  def resolve
    @anomaly_detection.resolve!

    # Invalidate relevant caches
    invalidate_anomaly_caches

    # Set no-cache headers to prevent stale data in subsequent requests
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render json: {
      message: "Anomaly resolved successfully",
      anomaly_detection: anomaly_detection_json(@anomaly_detection)
    }
  end

  def destroy
    @anomaly_detection.destroy

    # Invalidate relevant caches
    invalidate_anomaly_caches

    head :no_content
  end

  private

  def set_anomaly_detection
    @anomaly_detection = AnomalyDetection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Anomaly detection not found" }, status: :not_found
  end

  def anomaly_detection_params
    params.require(:anomaly_detection).permit(:transaction_record_id, :anomaly_type, :severity, :description, :resolved, :metadata)
  end

  def anomaly_detection_json(anomaly_detection, include_transaction: false)
    json = {
      id: anomaly_detection.id,
      anomaly_type: anomaly_detection.anomaly_type,
      severity: anomaly_detection.severity,
      severity_label: anomaly_detection.severity_label,
      description: anomaly_detection.description,
      resolved: anomaly_detection.resolved,
      detected_at: anomaly_detection.detected_at,
      resolved_at: anomaly_detection.resolved_at,
      metadata: anomaly_detection.metadata,
      created_at: anomaly_detection.created_at,
      updated_at: anomaly_detection.updated_at,
      transaction_id: anomaly_detection.transaction_record_id
    }

    if include_transaction && anomaly_detection.transaction_record
      transaction = anomaly_detection.transaction_record
      json[:transaction] = {
        id: transaction.id,
        amount: transaction.amount.to_f,
        description: transaction.description,
        transaction_date: transaction.transaction_date,
        status: transaction.status,
        category: transaction.category&.name
      }
    end

    json
  end

  def invalidate_anomaly_caches
    # Clear dashboard statistics cache
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete("recent_transactions")
    Rails.cache.delete("total_transactions_count")
    Rails.cache.delete("total_amount_sum")
    Rails.cache.delete("monthly_transaction_trends")
    Rails.cache.delete("category_breakdown")

    # Clear anomaly detection caches
    Rails.cache.delete_matched("anomaly_detections_*")
    Rails.cache.delete_matched("transactions_anomalies_*")

    # Clear transaction index caches (pattern-based deletion)
    Rails.cache.delete_matched("transactions_index_*")
    Rails.cache.delete_matched("total_transactions_filtered_*")
  end
end
