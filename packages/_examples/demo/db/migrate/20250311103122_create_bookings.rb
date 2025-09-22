class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.references :car, null: false, foreign_key: true
      t.integer :customer_id
      t.datetime :start_date
      t.datetime :end_date

      t.timestamps
    end
  end
end
