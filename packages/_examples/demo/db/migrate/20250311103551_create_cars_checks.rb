class CreateCarsChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :cars_checks do |t|
      t.references :car, null: false, foreign_key: true
      t.references :check, null: false, foreign_key: true
    end
  end
end
