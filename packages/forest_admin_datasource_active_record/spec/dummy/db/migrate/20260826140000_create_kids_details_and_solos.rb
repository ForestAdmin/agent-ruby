class CreateKidsDetailsAndSolos < ActiveRecord::Migration[7.1]
  def change
    create_table :parents
    create_table :solos

    create_table :kids do |t|
      t.references :owner, polymorphic: true
    end

    create_table :details do |t|
      t.integer :custom_kid_id
    end
  end
end
