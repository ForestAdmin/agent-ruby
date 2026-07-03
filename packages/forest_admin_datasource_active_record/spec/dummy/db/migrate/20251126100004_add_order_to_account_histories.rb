class AddOrderToAccountHistories < ActiveRecord::Migration[7.1]
  def change
    add_reference :account_histories, :order, null: true, foreign_key: true
  end
end
