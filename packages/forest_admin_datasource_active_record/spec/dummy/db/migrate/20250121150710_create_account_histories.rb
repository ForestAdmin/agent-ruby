# frozen_string_literal: true

class CreateAccountHistories < ActiveRecord::Migration[7.1]
  def change
    create_table :account_histories do |t|
      # t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
