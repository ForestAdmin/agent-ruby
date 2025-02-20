class CreateCompanies < ActiveRecord::Migration[7.0]
  def change
    create_table :companies do |t|
      t.column :name, :string
      t.timestamps
    end
  end
end
