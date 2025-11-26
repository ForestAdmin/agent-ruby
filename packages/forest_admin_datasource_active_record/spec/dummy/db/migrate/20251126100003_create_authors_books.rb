class CreateAuthorsBooks < ActiveRecord::Migration[7.0]
  def change
    # Create join table WITH id column (default behavior)
    # This simulates the real-world scenario where join tables have id columns
    create_table :authors_books do |t|
      t.references :author, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.timestamps
    end
  end
end
