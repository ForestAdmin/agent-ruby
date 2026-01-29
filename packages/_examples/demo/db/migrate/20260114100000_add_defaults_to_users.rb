class AddDefaultsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :active, :boolean, default: false
    add_column :users, :verified, :boolean, default: true
    add_column :users, :status, :integer, default: 0
    add_column :users, :role, :integer, default: 1
  end
end
