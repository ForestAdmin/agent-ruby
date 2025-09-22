class CreateCompaniesUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :companies_users, id: false do |t|
      t.belongs_to :company
      t.belongs_to :user
    end
  end
end
