class CreateAddresses < ActiveRecord::Migration[7.0]
  def change
    create_table :addresses do |t|
      t.string :city
      t.string :zip_code
      t.string :street
      t.references :addressable, polymorphic: true
      t.timestamps
    end
  end
end
