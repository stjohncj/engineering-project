class AddFieldsToAnomalyDetections < ActiveRecord::Migration[8.0]
  def change
    add_column :anomaly_detections, :metadata, :json
    add_column :anomaly_detections, :detected_at, :datetime
    add_column :anomaly_detections, :resolved_at, :datetime
  end
end
