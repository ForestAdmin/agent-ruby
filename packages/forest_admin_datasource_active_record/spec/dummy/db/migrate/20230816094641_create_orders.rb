class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.string :reference
      t.binary :invoice

      t.timestamps
    end
  end
end
