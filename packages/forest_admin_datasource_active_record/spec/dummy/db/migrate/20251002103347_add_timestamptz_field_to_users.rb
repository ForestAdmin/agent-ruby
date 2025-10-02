class AddTimestamptzFieldToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :timestamptz_field, :timestamptz
  end
end
