class Api::V1::TransactionsController < ApplicationController
  before_action :set_transaction, only: [:show, :update, :destroy]
  
  def index
    @transactions = Transaction.includes(:category, :anomaly_detections)
    
    # Filtering
    @transactions = @transactions.where(category_id: params[:category_id]) if params[:category_id].present?
    @transactions = @transactions.where(status: params[:status]) if params[:status].present?
    @transactions = @transactions.by_date_range(params[:start_date], params[:end_date]) if params[:start_date] && params[:end_date]
    @transactions = @transactions.by_amount_range(params[:min_amount], params[:max_amount]) if params[:min_amount] && params[:max_amount]
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 50, 100].min
    offset = (page - 1) * per_page
    
    @transactions = @transactions.offset(offset).limit(per_page).order(transaction_date: :desc, created_at: :desc)
    
    render json: {
      transactions: @transactions.map { |t| transaction_json(t) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: Transaction.count
      }
    }
  end
  
  def show
    render json: { transaction: transaction_json(@transaction) }
  end
  
  def create
    @transaction = Transaction.new(transaction_params)
    
    if @transaction.save
      # Apply categorization rules
      apply_rules(@transaction)
      # Check for anomalies
      AnomalyDetectionService.new(@transaction).detect_and_flag
      
      render json: { transaction: transaction_json(@transaction) }, status: :created
    else
      render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def update
    if @transaction.update(transaction_params)
      render json: { transaction: transaction_json(@transaction) }
    else
      render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def destroy
    @transaction.destroy
    head :no_content
  end
  
  def bulk_update
    transaction_ids = params[:transaction_ids]
    updates = params[:updates] || {}
    
    begin
      Transaction.transaction do
        transactions = Transaction.where(id: transaction_ids)
        
        if updates[:category_id].present?
          transactions.update_all(category_id: updates[:category_id])
        end
        
        if updates[:status].present?
          transactions.update_all(status: updates[:status])
        end
        
        updated_transactions = transactions.reload
        render json: {
          message: "#{updated_transactions.count} transactions updated successfully",
          transactions: updated_transactions.map { |t| transaction_json(t) }
        }
      end
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  
  def import_csv
    if params[:file].blank?
      return render json: { error: "No CSV file provided" }, status: :unprocessable_entity
    end
    
    begin
      result = CsvImportService.new(params[:file]).import
      render json: {
        message: "CSV import completed",
        imported: result[:imported],
        failed: result[:failed],
        errors: result[:errors]
      }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  
  def anomalies
    @transactions = Transaction.with_anomalies.includes(:category, :anomaly_detections)
    render json: {
      transactions: @transactions.map { |t| transaction_json(t, include_anomalies: true) }
    }
  end
  
  private
  
  def set_transaction
    @transaction = Transaction.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Transaction not found" }, status: :not_found
  end
  
  def transaction_params
    params.require(:transaction).permit(:amount, :description, :transaction_date, :category_id, :status)
  end
  
  def transaction_json(transaction, include_anomalies: false)
    json = {
      id: transaction.id,
      amount: transaction.amount.to_f,
      description: transaction.description,
      transaction_date: transaction.transaction_date,
      status: transaction.status,
      category: transaction.category&.name,
      category_id: transaction.category_id,
      created_at: transaction.created_at,
      updated_at: transaction.updated_at
    }
    
    if include_anomalies || transaction.has_anomalies?
      json[:anomalies] = transaction.flagged_anomalies.map do |anomaly|
        {
          id: anomaly.id,
          type: anomaly.anomaly_type,
          severity: anomaly.severity,
          severity_label: anomaly.severity_label,
          description: anomaly.description,
          resolved: anomaly.resolved
        }
      end
    end
    
    json
  end
  
  def apply_rules(transaction)
    Rule.active.each do |rule|
      rule.apply_to!(transaction)
    end
  end
end