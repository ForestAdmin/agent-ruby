class CreateJoinTableCarCheck < ActiveRecord::Migration[7.0]
  def change
    create_table :car_checks do |t|
      t.references :car, null: false, foreign_key: true
      t.references :check, null: false, foreign_key: true
    end
  end
end
