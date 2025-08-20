class Api::V1::TransactionsController < ApplicationController
  include Paginatable
  
  before_action :set_transaction, only: [:show, :update, :destroy]
  
  def index
    # Cache key based on params for filtered results
    cache_key = "transactions_index_#{Digest::MD5.hexdigest(params.to_query)}"
    
    result = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      # Build base query with eager loading to prevent N+1 queries
      @transactions = Transaction.includes(:category, :anomaly_detections)
      
      # Apply filters efficiently using indexed columns
      @transactions = apply_filters(@transactions)
      
      # Apply sorting for consistent pagination
      @transactions = @transactions.order(transaction_date: :desc, created_at: :desc)
      
      # Paginate the collection
      paginated_transactions = paginate_collection(@transactions)
      
      # Generate paginated response
      paginated_json(
        paginated_transactions.map { |t| transaction_json(t) },
        data_key: :transactions
      )
    end
    
    # Set HTTP cache headers
    expires_in 2.minutes, public: true
    render json: result
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
      
      # Invalidate relevant caches
      invalidate_transaction_caches
      
      render json: { transaction: transaction_json(@transaction) }, status: :created
    else
      render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def update
    if @transaction.update(transaction_params)
      # Invalidate relevant caches
      invalidate_transaction_caches
      
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
    
    # Check if async processing is requested
    if params[:async] == 'true'
      import_csv_async
    else
      import_csv_sync
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
  
  def apply_filters(relation)
    # Apply filters using indexed columns for optimal performance
    relation = relation.where(category_id: params[:category_id]) if params[:category_id].present?
    relation = relation.where(status: params[:status]) if params[:status].present?
    relation = relation.by_date_range(params[:start_date], params[:end_date]) if params[:start_date] && params[:end_date]
    relation = relation.by_amount_range(params[:min_amount], params[:max_amount]) if params[:min_amount] && params[:max_amount]
    
    # Add text search if provided
    if params[:search].present?
      relation = relation.where("description ILIKE ?", "%#{params[:search]}%")
    end
    
    relation
  end
  
  def import_csv_sync
    begin
      result = CsvImportService.new(params[:file]).import
      render json: {
        message: "CSV import completed",
        imported: result[:imported],
        failed: result[:failed],
        errors: result[:errors],
        batch_id: result[:batch_id]
      }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  
  def import_csv_async
    begin
      # Save uploaded file to temporary location
      temp_file = Rails.root.join('tmp', "csv_import_#{Time.current.to_i}_#{SecureRandom.hex(8)}.csv")
      File.open(temp_file, 'wb') do |file|
        file.write(params[:file].read)
      end
      
      # Queue the import job
      job_id = CsvImportJob.perform_later(
        temp_file.to_s,
        1, # Default user_id for now - implement proper authentication later
        run_anomaly_detection: params[:run_anomaly_detection] == 'true'
      ).job_id
      
      render json: {
        message: "CSV import queued for background processing",
        job_id: job_id,
        status: "queued"
      }, status: :accepted
      
    rescue => e
      # Clean up temp file if it was created
      File.delete(temp_file) if temp_file && File.exist?(temp_file)
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  
  def current_user_id
    # Placeholder - implement based on your authentication system
    # For now, return a default value or session-based ID
    session[:user_id] || 'anonymous'
  end
  
  def invalidate_transaction_caches
    # Clear dashboard statistics cache
    Rails.cache.delete("dashboard_statistics")
    Rails.cache.delete("recent_transactions")
    Rails.cache.delete("total_transactions_count")
    Rails.cache.delete("total_amount_sum")
    Rails.cache.delete("monthly_transaction_trends")
    Rails.cache.delete("category_breakdown")
    
    # Clear transaction index caches (pattern-based deletion)
    Rails.cache.delete_matched("transactions_index_*")
    Rails.cache.delete_matched("total_transactions_filtered_*")
  end
end