class Api::V1::TransactionsController < ApplicationController
  include Paginatable

  before_action :set_transaction, only: [ :show, :update, :destroy ]

  def index
    # Build base query with eager loading to prevent N+1 queries
    @transactions = Transaction.includes(:category, :anomaly_detections)

    # Apply filters efficiently using indexed columns
    @transactions = apply_filters(@transactions)

    # Apply sorting for consistent pagination
    @transactions = @transactions.order(transaction_date: :desc, created_at: :desc)

    # Get current page and per_page params
    page = params[:page]&.to_i || 1
    per_page = [ (params[:per_page]&.to_i || 50), 100 ].min

    # Use Kaminari for pagination
    paginated_transactions = @transactions.page(page).per(per_page)

    # Get total count manually to ensure accuracy
    total_count = @transactions.except(:limit, :offset, :order).count
    total_pages = (total_count.to_f / per_page).ceil

    # Convert to JSON
    transactions_data = paginated_transactions.map { |t| transaction_json(t) }

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
      transactions: transactions_data,
      pagination: pagination_info
    }

    # Set HTTP cache headers
    expires_in 2.minutes, public: true
    render json: result
  end

  def show
    render json: { transaction: transaction_json(@transaction) }
  end

  def create
    @transaction = Transaction.new(transaction_params)

    # Handle category assignment by name if provided
    if params[:transaction][:category_name].present?
      category = Category.find_or_create_by(name: params[:transaction][:category_name])
      @transaction.category = category
    end

    if @transaction.save
      # Apply categorization rules
      apply_rules(@transaction)
      # Check for anomalies
      AnomalyDetectionService.new(@transaction).detect_and_flag

      # Invalidate relevant caches
      invalidate_transaction_caches

      render json: { transaction: transaction_json(@transaction) }, status: :created
    else
      render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @transaction.update(transaction_params)
      # Invalidate relevant caches
      invalidate_transaction_caches

      # Set no-cache headers to prevent stale data in subsequent requests
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"

      render json: { transaction: transaction_json(@transaction) }
    else
      render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @transaction.destroy

    # Invalidate relevant caches
    invalidate_transaction_caches

    # Set no-cache headers to prevent stale data in subsequent requests
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

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

        # Invalidate relevant caches
        invalidate_transaction_caches

        # Set no-cache headers to prevent stale data in subsequent requests
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"

        render json: {
          message: "#{updated_transactions.count} transactions updated successfully",
          transactions: updated_transactions.map { |t| transaction_json(t) }
        }
      end
    rescue => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def import_csv
    if params[:file].blank?
      return render json: { error: "No CSV file provided" }, status: :unprocessable_content
    end

    # Check if async processing is requested
    if params[:async] == "true"
      import_csv_async
    else
      import_csv_sync
    end
  end

  def anomalies
    # Build base query based on show_all and with_anomalies_only parameters
    if params[:show_all] == "true"
      # Show all transactions regardless of anomalies
      @transactions = Transaction.includes(:category)
    elsif params[:with_anomalies_only] == "true"
      # Show only transactions with anomalies (explicit request)
      @transactions = Transaction.with_anomalies.includes(:category)
    else
      # Default behavior: show transactions with anomalies
      @transactions = Transaction.with_anomalies.includes(:category)
    end

    # Apply status filter if provided
    if params[:status].present?
      @transactions = @transactions.where(status: params[:status])
    end

    # Apply additional filters
    @transactions = apply_anomalies_filters(@transactions)

    # Apply sorting
    @transactions = @transactions.order(transaction_date: :desc, created_at: :desc)

    # Get current page and per_page params
    page = params[:page]&.to_i || 1
    per_page = [ (params[:per_page]&.to_i || 50), 100 ].min

    # Use Kaminari for pagination
    paginated_transactions = @transactions.page(page).per(per_page)

    # Get total count manually to ensure accuracy
    total_count = @transactions.except(:limit, :offset, :order).count
    total_pages = (total_count.to_f / per_page).ceil

    # Convert to JSON - load anomaly_detections separately to avoid JSON field issues
    transactions_data = paginated_transactions.map do |t|
      transaction_json(t, include_anomalies: true)
    end

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
      transactions: transactions_data,
      pagination: pagination_info
    }

    render json: result
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
      # Load anomalies without the problematic JSON metadata field
      anomalies = AnomalyDetection.where(
        transaction_record_id: transaction.id,
        resolved: false
      ).select(:id, :anomaly_type, :severity, :description, :resolved)

      json[:anomalies] = anomalies.map do |anomaly|
        {
          id: anomaly.id,
          type: anomaly.anomaly_type,
          severity: anomaly.severity,
          severity_label: case anomaly.severity
                          when 1 then "Low"
                          when 2 then "Low-Medium"
                          when 3 then "Medium"
                          when 4 then "High"
                          when 5 then "Critical"
                          end,
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

    # Filter by category name if provided
    if params[:category].present?
      relation = relation.joins(:category).where(categories: { name: params[:category] })
    end

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

      # Format response to match frontend expectations
      processed_count = result[:imported] + result[:failed]
      duplicate_count = result[:errors]&.count { |error| error.include?("Duplicate") } || 0
      error_count = result[:failed] - duplicate_count

      render json: {
        message: "CSV import completed",
        processed_count: processed_count,
        imported_count: result[:imported],
        duplicate_count: duplicate_count,
        error_count: error_count,
        anomaly_count: 0, # TODO: Implement anomaly detection count
        batch_id: result[:batch_id],
        # Keep original format for backward compatibility
        imported: result[:imported],
        failed: result[:failed],
        errors: result[:errors]
      }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def import_csv_async
    begin
      # Save uploaded file to temporary location
      temp_file = Rails.root.join("tmp", "csv_import_#{Time.current.to_i}_#{SecureRandom.hex(8)}.csv")

      # Handle different file upload types
      file_content = if params[:file].respond_to?(:read)
                      params[:file].read
      elsif params[:file].respond_to?(:tempfile)
                      params[:file].tempfile.read
      else
                      raise "Invalid file parameter: #{params[:file].class}"
      end

      File.open(temp_file, "wb") do |file|
        file.write(file_content)
      end

      # Queue the import job
      job_id = CsvImportJob.perform_later(
        temp_file.to_s,
        "anonymous", # Default user for now - implement proper authentication later
        run_anomaly_detection: params[:run_anomaly_detection] == "true"
      ).job_id

      render json: {
        message: "CSV import queued for background processing",
        job_id: job_id,
        status: "queued"
      }, status: :accepted

    rescue => e
      # Clean up temp file if it was created
      File.delete(temp_file) if temp_file && File.exist?(temp_file)
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def current_user_id
    # Placeholder - implement based on your authentication system
    # For now, return a default value or session-based ID
    session[:user_id] || "anonymous"
  end

  def cache_params
    # Only include cacheable filter parameters
    params.permit(:category_id, :status, :start_date, :end_date, :min_amount, :max_amount, :search, :page, :per_page).to_h
  end

  def apply_anomalies_filters(relation)
    # Filter by anomaly type if specified
    if params[:anomaly_type].present?
      relation = relation.joins(:anomaly_detections)
                        .where(anomaly_detections: { anomaly_type: params[:anomaly_type] })
                        .distinct
    end

    # Filter by severity if specified
    if params[:severity].present?
      relation = relation.joins(:anomaly_detections)
                        .where(anomaly_detections: { severity: params[:severity] })
                        .distinct
    end

    relation
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
