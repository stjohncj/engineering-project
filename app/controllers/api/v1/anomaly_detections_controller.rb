class Api::V1::AnomalyDetectionsController < ApplicationController
  include Paginatable
  
  before_action :set_anomaly_detection, only: [:show, :update, :resolve]
  
  def index
    # Cache anomaly detections for 3 minutes
    cache_key = "anomaly_detections_index_#{Digest::MD5.hexdigest(params.to_query)}"
    
    result = Rails.cache.fetch(cache_key, expires_in: 3.minutes) do
      # Build query with eager loading
      @anomaly_detections = AnomalyDetection.includes(transaction_record: :category)
      
      # Apply filters efficiently
      @anomaly_detections = @anomaly_detections.where(resolved: false) if params[:unresolved] == 'true'
      @anomaly_detections = @anomaly_detections.by_severity(params[:severity]) if params[:severity].present?
      @anomaly_detections = @anomaly_detections.by_type(params[:anomaly_type]) if params[:anomaly_type].present?
      
      # Order by priority (severity desc, then creation time)
      @anomaly_detections = @anomaly_detections.order(severity: :desc, created_at: :desc)
      
      # Paginate efficiently
      paginated_anomalies = paginate_collection(@anomaly_detections)
      
      paginated_json(
        paginated_anomalies.map { |ad| anomaly_detection_json(ad) },
        data_key: :anomaly_detections
      )
    end
    
    expires_in 3.minutes, public: true
    render json: result
  end
  
  def show
    render json: { anomaly_detection: anomaly_detection_json(@anomaly_detection, include_transaction: true) }
  end
  
  def update
    if @anomaly_detection.update(anomaly_detection_params)
      render json: { anomaly_detection: anomaly_detection_json(@anomaly_detection) }
    else
      render json: { errors: @anomaly_detection.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def resolve
    @anomaly_detection.resolve!
    render json: { 
      message: "Anomaly resolved successfully",
      anomaly_detection: anomaly_detection_json(@anomaly_detection) 
    }
  end
  
  private
  
  def set_anomaly_detection
    @anomaly_detection = AnomalyDetection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Anomaly detection not found" }, status: :not_found
  end
  
  def anomaly_detection_params
    params.require(:anomaly_detection).permit(:resolved)
  end
  
  def anomaly_detection_json(anomaly_detection, include_transaction: false)
    json = {
      id: anomaly_detection.id,
      anomaly_type: anomaly_detection.anomaly_type,
      severity: anomaly_detection.severity,
      severity_label: anomaly_detection.severity_label,
      description: anomaly_detection.description,
      resolved: anomaly_detection.resolved,
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
end