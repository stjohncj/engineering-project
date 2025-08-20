class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for common query patterns
    add_index :transactions, [:transaction_date, :status], name: 'index_transactions_on_date_and_status'
    add_index :transactions, [:category_id, :transaction_date], name: 'index_transactions_on_category_and_date'
    add_index :transactions, [:amount, :transaction_date], name: 'index_transactions_on_amount_and_date'
    add_index :transactions, [:status, :created_at], name: 'index_transactions_on_status_and_created_at'
    
    # Partial indexes for common filters
    add_index :transactions, :transaction_date, where: "category_id IS NULL", name: 'index_transactions_uncategorized_by_date'
    add_index :transactions, :amount, where: "amount > 1000", name: 'index_transactions_large_amounts'
    
    # Full-text search index for descriptions (PostgreSQL specific)
    if connection.adapter_name == 'PostgreSQL'
      execute "CREATE INDEX CONCURRENTLY index_transactions_description_fulltext ON transactions USING gin(to_tsvector('english', description))"
    end
    
    # Anomaly detection performance indexes
    add_index :anomaly_detections, [:resolved, :severity, :created_at], name: 'index_anomaly_detections_on_resolved_severity_created'
    add_index :anomaly_detections, [:transaction_record_id, :resolved], name: 'index_anomaly_detections_on_transaction_and_resolved'
    
    # Categories performance indexes
    add_index :categories, :name, unique: true, name: 'index_categories_on_name_unique'
    
    # Rules performance indexes  
    add_index :rules, [:active, :created_at], name: 'index_rules_on_active_and_created'
  end
  
  def down
    remove_index :transactions, name: 'index_transactions_on_date_and_status'
    remove_index :transactions, name: 'index_transactions_on_category_and_date'
    remove_index :transactions, name: 'index_transactions_on_amount_and_date'
    remove_index :transactions, name: 'index_transactions_on_status_and_created_at'
    remove_index :transactions, name: 'index_transactions_uncategorized_by_date'
    remove_index :transactions, name: 'index_transactions_large_amounts'
    
    if connection.adapter_name == 'PostgreSQL'
      execute "DROP INDEX CONCURRENTLY IF EXISTS index_transactions_description_fulltext"
    end
    
    remove_index :anomaly_detections, name: 'index_anomaly_detections_on_resolved_severity_created'
    remove_index :anomaly_detections, name: 'index_anomaly_detections_on_transaction_and_resolved'
    remove_index :categories, name: 'index_categories_on_name_unique'
    remove_index :rules, name: 'index_rules_on_active_and_created'
  end
end