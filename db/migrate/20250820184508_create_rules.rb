class CreateRules < ActiveRecord::Migration[8.0]
  def change
    create_table :rules do |t|
      t.string :name
      t.string :condition_field
      t.string :condition_operator
      t.string :condition_value
      t.string :action_type
      t.string :action_value
      t.boolean :active

      t.timestamps
    end
  end
end
