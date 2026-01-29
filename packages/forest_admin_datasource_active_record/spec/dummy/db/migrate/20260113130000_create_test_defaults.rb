class CreateTestDefaults < ActiveRecord::Migration[7.0]
  def change
    create_table :test_defaults do |t|
      t.boolean :active, default: false
      t.boolean :verified, default: true
      t.integer :status, default: 0
      t.integer :priority, default: 1
      t.string :name

      t.timestamps
    end
  end
end
