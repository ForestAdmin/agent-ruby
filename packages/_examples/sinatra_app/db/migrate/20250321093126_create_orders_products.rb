class CreateOrdersProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :orders_products, id: false do |t|
      t.belongs_to :order
      t.belongs_to :product
    end
  end
end
