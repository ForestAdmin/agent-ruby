class CreateRentCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :rent_companies do |t|
      t.string :name

      t.timestamps
    end
  end
end
