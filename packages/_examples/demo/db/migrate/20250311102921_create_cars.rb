class CreateCars < ActiveRecord::Migration[8.0]
  def change
    create_table :cars do |t|
      t.references :category, null: false, foreign_key: true
      t.string :reference
      t.string :model
      t.string :brand
      t.integer :year
      t.integer :nb_seats
      t.boolean :is_manual
      t.json :options

      t.integer :rent_company_id

      t.timestamps
    end
  end
end
