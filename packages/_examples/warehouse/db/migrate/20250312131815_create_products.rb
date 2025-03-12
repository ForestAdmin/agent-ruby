class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :label
      t.integer :quantity
      t.references :manufacturer, null: false, foreign_key: true
      t.date :next_restocking_date

      t.timestamps
    end
  end
end
