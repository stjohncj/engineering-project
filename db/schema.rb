# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_20_195449) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "anomaly_detections", force: :cascade do |t|
    t.integer "transaction_record_id", null: false
    t.string "anomaly_type"
    t.integer "severity"
    t.text "description"
    t.boolean "resolved"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata"
    t.datetime "detected_at"
    t.datetime "resolved_at"
    t.index ["transaction_record_id"], name: "index_anomaly_detections_on_transaction_record_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rules", force: :cascade do |t|
    t.string "name"
    t.string "condition_field"
    t.string "condition_operator"
    t.string "condition_value"
    t.string "action_type"
    t.string "action_value"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "description"
    t.date "transaction_date", null: false
    t.integer "category_id"
    t.integer "status", default: 0
    t.text "anomaly_flags"
    t.string "import_batch_id"
    t.string "duplicate_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["amount"], name: "index_transactions_on_amount"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["duplicate_hash"], name: "index_transactions_on_duplicate_hash"
    t.index ["import_batch_id"], name: "index_transactions_on_import_batch_id"
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["transaction_date"], name: "index_transactions_on_transaction_date"
  end

  add_foreign_key "anomaly_detections", "transactions", column: "transaction_record_id"
  add_foreign_key "transactions", "categories"
end
