class AnomalyDetectionService
  def initialize(transaction)
    @transaction = transaction
    @anomalies = []
  end

  def detect_and_flag
    detect_unusual_amount
    detect_potential_duplicates
    detect_incomplete_metadata
    apply_active_rules

    create_anomaly_records
  end

  private

  def detect_unusual_amount
    return unless @transaction.amount

    # Get user's historical transaction statistics
    historical_stats = calculate_historical_stats

    if historical_stats[:count] >= 10 # Need sufficient data
      amount = @transaction.amount.to_f

      # Check if amount is significantly higher than usual
      if amount > historical_stats[:mean] + (2 * historical_stats[:std_dev])
        severity = calculate_amount_anomaly_severity(amount, historical_stats)
        @anomalies << {
          type: "unusual_amount",
          severity: severity,
          description: "Transaction amount (#{format_currency(amount)}) is significantly higher than typical spending (avg: #{format_currency(historical_stats[:mean])})",
          metadata: {
            historical_average: historical_stats[:mean],
            standard_deviation: historical_stats[:std_dev],
            z_score: (amount - historical_stats[:mean]) / historical_stats[:std_dev]
          }
        }
      end

      # Check if amount is significantly lower than usual
      if amount < historical_stats[:mean] - (2 * historical_stats[:std_dev]) && amount > 0
        severity = calculate_amount_anomaly_severity(amount, historical_stats)
        @anomalies << {
          type: "unusual_amount",
          severity: severity,
          description: "Transaction amount (#{format_currency(amount)}) is significantly lower than typical spending (avg: #{format_currency(historical_stats[:mean])})",
          metadata: {
            historical_average: historical_stats[:mean],
            standard_deviation: historical_stats[:std_dev],
            z_score: (amount - historical_stats[:mean]) / historical_stats[:std_dev]
          }
        }
      end

      # Check for very large amounts
      if amount > 10000
        @anomalies << {
          type: "unusual_amount",
          severity: 4,
          description: "Large transaction amount: #{format_currency(amount)}",
          metadata: {
            historical_average: historical_stats[:mean],
            threshold_exceeded: "large_amount_threshold"
          }
        }
      end
    end
  end

  def detect_potential_duplicates
    # Check for transactions with same amount, date, and similar description
    similar_transactions = Transaction.where(
      amount: @transaction.amount,
      transaction_date: @transaction.transaction_date
    ).where.not(id: @transaction.id)

    similar_transactions.each do |similar|
      similarity = calculate_description_similarity(@transaction.description, similar.description)

      if similarity > 0.8 # 80% similarity threshold
        @anomalies << {
          type: "potential_duplicate",
          severity: 3,
          description: "Potential duplicate of transaction ##{similar.id} with #{(similarity * 100).round}% similarity",
          metadata: { similar_transaction_id: similar.id, similarity_score: similarity }
        }
      end
    end

    # Check for exact duplicates by hash
    duplicate = Transaction.where(duplicate_hash: @transaction.duplicate_hash).where.not(id: @transaction.id).first
    if duplicate
      @anomalies << {
        type: "potential_duplicate",
        severity: 5,
        description: "Exact duplicate transaction detected (same amount, date, and description)",
        metadata: { similar_transaction_id: duplicate.id, similarity_score: 1.0 }
      }
    end
  end

  def detect_incomplete_metadata
    issues = []

    issues << "Missing description" if @transaction.description.blank?
    issues << "Very short description" if @transaction.description.present? && @transaction.description.length < 3
    issues << "Missing category" if @transaction.category.blank?

    if issues.any?
      @anomalies << {
        type: "incomplete_metadata",
        severity: 2,
        description: "Incomplete transaction data: #{issues.join(', ')}"
      }
    end
  end

  def apply_active_rules
    # Get all active rules and apply them to the transaction
    Rule.active.each do |rule|
      begin
        rule.apply_to!(@transaction)
      rescue => e
        Rails.logger.error "Failed to apply rule #{rule.id} (#{rule.name}) to transaction #{@transaction.id}: #{e.message}"
        # Continue with other rules even if one fails
      end
    end
  end

  def calculate_historical_stats
    # Get last 90 days of transactions (excluding current one)
    historical = Transaction.where(
      "transaction_date >= ? AND id != ?",
      90.days.ago,
      @transaction.id || 0
    )

    amounts = historical.pluck(:amount).map(&:to_f)

    return { count: 0, mean: 0, std_dev: 0 } if amounts.empty?

    mean = amounts.sum / amounts.length
    variance = amounts.map { |amount| (amount - mean) ** 2 }.sum / amounts.length
    std_dev = Math.sqrt(variance)

    {
      count: amounts.length,
      mean: mean,
      std_dev: std_dev,
      max: amounts.max,
      min: amounts.min
    }
  end

  def calculate_amount_anomaly_severity(amount, stats)
    z_score = (amount - stats[:mean]) / stats[:std_dev]
    abs_z_score = z_score.abs

    case abs_z_score
    when 0..2
      2
    when 2..3
      3
    when 3..4
      4
    else
      5
    end
  end

  def calculate_description_similarity(desc1, desc2)
    return 0.0 if desc1.blank? || desc2.blank?

    # Simple word-based similarity
    words1 = desc1.downcase.split(/\W+/).reject(&:blank?)
    words2 = desc2.downcase.split(/\W+/).reject(&:blank?)

    return 1.0 if words1 == words2

    intersection = words1 & words2
    union = words1 | words2

    return 0.0 if union.empty?

    intersection.length.to_f / union.length
  end

  def create_anomaly_records
    created_records = []

    @anomalies.each do |anomaly_data|
      record = AnomalyDetection.create!(
        transaction_record: @transaction,
        anomaly_type: anomaly_data[:type],
        severity: anomaly_data[:severity],
        description: anomaly_data[:description],
        metadata: anomaly_data[:metadata],
        resolved: false
      )
      created_records << record
    end

    # Update transaction status if any anomalies are detected
    if @anomalies.any?
      @transaction.update!(status: :flagged)
    end

    created_records
  end

  def format_currency(amount)
    "$#{amount.round(2)}"
  end
end
