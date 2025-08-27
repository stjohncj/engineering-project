class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :description
      t.date :transaction_date, null: false
      t.references :category, null: true, foreign_key: true
      t.integer :status, default: 0
      t.text :anomaly_flags
      t.string :import_batch_id
      t.string :duplicate_hash

      t.timestamps
    end

    add_index :transactions, :transaction_date
    add_index :transactions, :amount
    add_index :transactions, :status
    add_index :transactions, :duplicate_hash
    add_index :transactions, :import_batch_id
  end
end
