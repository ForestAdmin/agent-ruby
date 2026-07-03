class AddSecondaryHistoryToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :secondary_history_id, :integer, null: true
  end
end
