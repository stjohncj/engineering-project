class Api::V1::AnomalyDetectionsController < ApplicationController
  before_action :set_anomaly_detection, only: [:show, :update, :resolve]
  
  def index
    @anomaly_detections = AnomalyDetection.includes(:transaction_record)
    
    # Filtering
    @anomaly_detections = @anomaly_detections.where(resolved: false) if params[:unresolved] == 'true'
    @anomaly_detections = @anomaly_detections.by_severity(params[:severity]) if params[:severity].present?
    @anomaly_detections = @anomaly_detections.by_type(params[:anomaly_type]) if params[:anomaly_type].present?
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 50, 100].min
    offset = (page - 1) * per_page
    
    @anomaly_detections = @anomaly_detections.offset(offset).limit(per_page).order(severity: :desc, created_at: :desc)
    
    render json: {
      anomaly_detections: @anomaly_detections.map { |ad| anomaly_detection_json(ad) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: AnomalyDetection.count
      }
    }
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