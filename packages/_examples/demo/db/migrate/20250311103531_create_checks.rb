class CreateChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :checks do |t|
      t.string :garage_name
      t.date :date

      t.timestamps
    end
  end
end
