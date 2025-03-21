class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :reference
      t.decimal :total
      t.decimal :shipping_costs
      t.string :status
      t.timestamps
    end
  end
end
