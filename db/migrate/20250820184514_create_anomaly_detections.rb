class CreateAnomalyDetections < ActiveRecord::Migration[8.0]
  def change
    create_table :anomaly_detections do |t|
      t.references :transaction_record, null: false, foreign_key: { to_table: :transactions }
      t.string :anomaly_type
      t.integer :severity
      t.text :description
      t.boolean :resolved

      t.timestamps
    end
  end
end
